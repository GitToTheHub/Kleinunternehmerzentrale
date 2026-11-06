import { readFileSync } from "node:fs"
import { runInNewContext } from "node:vm"
import test from "node:test"
import assert from "node:assert/strict"

const source = readFileSync(new URL("../../app/javascript/controllers/invoice_number_controller.js", import.meta.url), "utf8")
const requests = []
const documentMock = {
  createElement: tagName => ({ tagName, dataset: {} }),
  createTextNode: textContent => ({ textContent }),
}
let respond
const InvoiceNumber = runInNewContext(source.replace(/^import .*\n/, "").replace("export default class", "globalThis.InvoiceNumber = class") + "\nInvoiceNumber", {
  Controller: class {}, AbortController, Event, URLSearchParams, setTimeout, clearTimeout,
  document: documentMock,
  fetch: (url, options) => { requests.push({ url, ...options }); return respond(url) },
})

async function setup() {
  requests.length = 0
  respond = async () => ({ ok: true, json: async () => ({ invoice_number: "RE-2027-0003" }) })
  const controller = new InvoiceNumber()
  const date = { value: "2026-10-07" }
  const kind = { value: "regular", dataset: { numberCode: "RE" } }
  controller.element = { querySelector: selector => selector === "#invoice_issued_on" ? date : kind, ownerDocument: documentMock }
  controller.numberTarget = { value: "RE-2026-0009" }
  controller.urlValue = "/rechnungen/naechste-nummer"
  for (const [name, value] of Object.entries({ format: "RE-[Jahr]-[Fortlaufendenummer]", abbreviation: "" })) {
    controller[`${name}Target`] = {
      value, selectionStart: value.length,
      setCustomValidity(message) { this.validationMessage = message },
      setSelectionRange(start) { this.selectionStart = start },
      addEventListener() {},
      removeEventListener() {},
    }
  }
  controller.abbreviationLabelTarget = {}
  controller.statusTarget = { replaceChildren(...children) { this.children = children } }
  controller.collisionHintTarget = { hidden: true }
  controller.connect()
  await controller.ready
  requests.length = 0
  return { controller, date, kind }
}

test("format edits can be undone and redone before the preview debounce finishes", async () => {
  const { controller } = await setup()
  const initial = controller.formatTarget.value
  controller.formatTarget.dispatchEvent = event => controller.update({ type: event.type, target: controller.formatTarget })
  controller.formatTarget.value += "X"
  await controller.update({ type: "input", target: controller.formatTarget })
  const event = { key: "z", ctrlKey: true, preventDefault() { this.defaultPrevented = true } }
  controller.undo(event)
  assert.equal(event.defaultPrevented, true)
  assert.equal(controller.formatTarget.value, initial)
  controller.undo({ ...event, shiftKey: true })
  assert.equal(controller.formatTarget.value, `${initial}X`)
  assert.equal(requests.length, 0)
  clearTimeout(controller.updateTimer)
})

test("changing the year retrieves the next number for that year", async () => {
  const { controller, date } = await setup()
  date.value = "2027-01-01"
  await controller.update()
  assert.equal(requests[0].url, "/rechnungen/naechste-nummer?issued_on=2027-01-01&invoice_number_format=RE-%5BJahr%5D-%5BFortlaufendenummer%5D&buyer_abbreviation=&billing_kind=regular")
  assert.equal(controller.numberTarget.value, "RE-2027-0003")
  date.value = "2027-12-31"
  await controller.update()
  assert.equal(requests.length, 2)
})

test("keeps the current invoice number visible while the next number is being calculated", async () => {
  const { controller, date } = await setup()
  const currentNumber = controller.numberTarget.value
  let finish
  respond = () => new Promise(resolve => { finish = resolve })
  date.value = "2027-01-01"
  const update = controller.update()
  assert.equal(controller.numberTarget.value, currentNumber)
  finish({ ok: true, json: async () => ({ invoice_number: "RE-2027-0003" }) })
  await update
  assert.equal(controller.numberTarget.value, "RE-2027-0003")
})

test("incomplete manual dates do not request a number", async () => {
  const { controller, date } = await setup()
  date.value = ""
  await controller.update()
  assert.equal(requests.length, 0)
})

test("older responses cannot overwrite a newer year", async () => {
  const { controller, date } = await setup()
  const finishes = []
  respond = () => new Promise(resolve => finishes.push(resolve))
  date.value = "2027-01-01"
  const first = controller.update()
  date.value = "2028-01-01"
  const second = controller.update()
  assert.equal(requests[0].signal.aborted, true)
  finishes[1]({ ok: true, json: async () => ({ invoice_number: "RE-2028-0001" }) })
  await second
  finishes[0]({ ok: true, json: async () => ({ invoice_number: "RE-2027-0003" }) })
  await first
  assert.equal(controller.numberTarget.value, "RE-2028-0001")
})

test("a failed lookup clears the old number and can be retried", async () => {
  const { controller, date } = await setup()
  respond = async () => ({ ok: false })
  date.value = "2027-01-01"
  await controller.update()
  assert.equal(controller.numberTarget.value, "Wird beim Erstellen vergeben")
  respond = async () => ({ ok: true, json: async () => ({ invoice_number: "RE-2027-0003" }) })
  await controller.update()
  assert.equal(controller.numberTarget.value, "RE-2027-0003")
})


test("custom formats require the customer abbreviation and report collisions", async () => {
  const { controller } = await setup()
  controller.formatTarget.value = "[Kundenkürzel]-[Jahr]-[Monat]-[Tag]"
  respond = async () => ({ ok: false, json: async () => ({ error: "Kürzel fehlt", field: "buyer_abbreviation" }) })
  await controller.update()
  assert.equal(controller.abbreviationTarget.required, true)
  assert.equal(controller.abbreviationTarget.validationMessage, "Kürzel fehlt")
  assert.equal(controller.collisionHintTarget.hidden, true)
  controller.abbreviationTarget.value = "BEG"
  respond = async () => ({ ok: false, json: async () => ({ error: "Nummer bereits vergeben", field: "invoice_number_format" }) })
  await controller.update()
  assert.equal(controller.abbreviationTarget.validationMessage, "")
  assert.equal(controller.formatTarget.validationMessage, "Nummer bereits vergeben")
  assert.equal(controller.statusTarget.hidden, true)
})

test("shows format errors only in the popup editor", async () => {
  const { controller } = await setup()
  const currentNumber = controller.numberTarget.value
  controller.editorStatusTarget = { hidden: true, textContent: "" }
  controller.hasEditorStatusTarget = true
  controller.formatTarget.value = "X".repeat(81)
  respond = async () => ({ ok: false, json: async () => ({ error: "Das Rechnungsnummernformat ist zu lang", field: "invoice_number_format" }) })
  await controller.update()
  assert.equal(controller.collisionHintTarget.hidden, true)
  assert.equal(controller.statusTarget.hidden, true)
  assert.equal(controller.editorStatusTarget.textContent, "Das Rechnungsnummernformat ist zu lang")
  assert.equal(controller.editorStatusTarget.hidden, false)
  assert.equal(controller.numberTarget.value, currentNumber)
})


test("formats without the annual counter show the collision hint", async () => {
  const { controller } = await setup()
  controller.formatTarget.value = "[Jahr]-[Monat]-[Tag]"
  await controller.update()
  assert.equal(controller.collisionHintTarget.hidden, false)
  assert.equal(controller.abbreviationTarget.required, false)
})


test("changing the starting counter refreshes the preview and reports invalid counters on the field", async () => {
  const { controller } = await setup()
  controller.hasStartTarget = true
  controller.startTarget = { value: "148", setCustomValidity(message) { this.validationMessage = message } }
  respond = async () => ({ ok: true, json: async () => ({ invoice_number: "RE-2026-0148" }) })
  await controller.update()
  assert.equal(new URL(requests[0].url, "http://localhost").searchParams.get("invoice_number_last"), "148")
  assert.equal(controller.numberTarget.value, "RE-2026-0148")
  controller.startTarget.value = "-1"
  respond = async () => ({ ok: false, json: async () => ({ error: "Ungültiger Zählerstand", field: "invoice_number_last" }) })
  await controller.update()
  assert.equal(controller.startTarget.validationMessage, "Ungültiger Zählerstand")
  controller.startTarget.value = ""
  respond = async () => ({ ok: true, json: async () => ({ invoice_number: "RE-2026-0001" }) })
  await controller.update()
  assert.equal(controller.startTarget.validationMessage, "")
  assert.equal(controller.numberTarget.value, "RE-2026-0001")
})


test("the next counter is filled automatically and follows the date until edited", async () => {
  const { controller, date } = await setup()
  controller.hasStartTarget = true
  controller.startTarget = { value: "", setCustomValidity() {} }
  controller.hasStartFieldTarget = true
  controller.startFieldTarget = {}
  controller.key = null
  respond = async () => ({ ok: true, json: async () => ({ invoice_number: "RE-2026-0042", sequence: 42 }) })
  await controller.update()
  assert.equal(controller.startTarget.value, "41")
  date.value = "2027-01-01"
  respond = async () => ({ ok: true, json: async () => ({ invoice_number: "RE-2027-0001", sequence: 1 }) })
  await controller.update()
  assert.equal(controller.startTarget.value, "0")
  assert.equal(new URL(requests.at(-1).url, "http://localhost").searchParams.has("invoice_number_last"), false)
  controller.startTarget.value = "148"
  respond = async () => ({ ok: true, json: async () => ({ invoice_number: "RE-2027-0148", sequence: 148 }) })
  await controller.update()
  assert.equal(controller.startTarget.value, "148")
  assert.equal(new URL(requests.at(-1).url, "http://localhost").searchParams.get("invoice_number_last"), "148")
  controller.formatTarget.value = "RE-[Jahr]-[Monat]-[Tag]"
  respond = async () => ({ ok: true, json: async () => ({ invoice_number: "RE-2027-01-01", sequence: null }) })
  await controller.update()
  assert.equal(controller.startTarget.disabled, true)
  assert.equal(controller.startTarget.value, "")
})

test("links the missing customer abbreviation error to its input", async () => {
  const { controller } = await setup()
  const message = "Bitte ergänze das Kundenkürzel"
  controller.abbreviationTarget = {
    focus() { this.focused = true },
    scrollIntoView(options) { this.scrollOptions = options },
  }
  controller.showStatus(message, "buyer_abbreviation")
  const link = controller.statusTarget.children[1]

  assert.equal(link.textContent, "Kundenkürzel")
  assert.equal(link.href, "#invoice_buyer_abbreviation")
  assert.equal(link.dataset.action, "click->invoice-number#focusAbbreviation")
  assert.equal(controller.statusTarget.children.map(child => child.textContent).join(""), message)
  const event = { preventDefault() { this.defaultPrevented = true } }
  controller.focusAbbreviation(event)
  assert.equal(event.defaultPrevented, true)
  assert.equal(controller.abbreviationTarget.focused, true)
  assert.equal(controller.abbreviationTarget.scrollOptions.behavior, "smooth")
  assert.equal(controller.abbreviationTarget.scrollOptions.block, "center")
})

test("formats without a counter cannot be adjusted through the annual counter field", async () => {
  const { controller } = await setup()
  controller.hasStartTarget = true
  controller.startTarget = { value: "148", setCustomValidity() {} }
  controller.formatTarget.value = "[Jahr]-[Monat]-[Tag]"
  respond = async () => ({ ok: true, json: async () => ({ invoice_number: "2026-10-07-01", sequence: 1 }) })
  await controller.update()
  assert.equal(controller.startTarget.disabled, true)
  assert.equal(controller.startTarget.value, "")
  assert.equal(new URL(requests.at(-1).url, "http://localhost").searchParams.has("invoice_number_last"), false)
})


test("daily counter templates show 01 and suppress the collision hint", async () => {
  const { controller } = await setup()
  const example = {}
  controller.presetTargets = [{ dataset: { format: "[Kundenkürzel]-[Jahr]-[Monat]-[Tag]-[Tageszähler]" }, setAttribute() {}, querySelector: () => example }]
  controller.formatTarget.value = controller.presetTargets[0].dataset.format
  controller.abbreviationTarget.value = "abe"
  await controller.update()
  assert.equal(example.textContent, "ABE-2026-10-07-01")
  assert.equal(controller.collisionHintTarget.hidden, true)
})


test("shows the next annual counter despite a missing abbreviation and preserves the entered last counter", async () => {
  const { controller } = await setup()
  controller.hasStartTarget = true
  controller.startTarget = { value: "1000", setCustomValidity(message) { this.validationMessage = message } }
  controller.hasNextCounterTarget = true
  controller.nextCounterTarget = {}
  controller.formatTarget.value = "RE-[Jahr]-[Fortlaufendenummer]-[Kundenkürzel]"
  respond = async () => ({ ok: false, json: async () => ({ error: "Kürzel fehlt", field: "buyer_abbreviation", sequence: 1001 }) })
  await controller.update()
  assert.equal(controller.nextCounterTarget.textContent, "Nächste fortlaufende Nummer: 1001")
  assert.equal(controller.startTarget.value, "1000")
  assert.equal(controller.abbreviationTarget.validationMessage, "Kürzel fehlt")
  assert.equal(new URL(requests.at(-1).url, "http://localhost").searchParams.get("invoice_number_last"), "1000")
  controller.abbreviationTarget.value = "MF"
  respond = async () => ({ ok: true, json: async () => ({ invoice_number: "RE-2026-1001-MF", sequence: 1001 }) })
  await controller.update()
  assert.equal(controller.numberTarget.value, "RE-2026-1001-MF")
  assert.equal(controller.nextCounterTarget.textContent, "Nächste fortlaufende Nummer: 1001")
  assert.equal(controller.abbreviationTarget.validationMessage, "")
})

test("fills the automatic last counter even when the abbreviation is still missing", async () => {
  const { controller } = await setup()
  controller.hasStartTarget = true
  controller.startTarget = { value: "", setCustomValidity() {} }
  controller.formatTarget.value = "RE-[Jahr]-[Fortlaufendenummer]-[Kundenkürzel]"
  respond = async () => ({ ok: false, json: async () => ({ error: "Kürzel fehlt", field: "buyer_abbreviation", sequence: 42 }) })
  await controller.update()
  assert.equal(controller.startTarget.value, "41")
  assert.equal(controller.autoStart, "41")
})

test("counter lookup ends its loading state on validation errors, incomplete dates and network failures", async () => {
  const { controller, date } = await setup()
  controller.hasStartTarget = true
  controller.startTarget = { value: "-1", setCustomValidity() {} }
  controller.hasNextCounterTarget = true
  controller.nextCounterTarget = {}
  respond = async () => ({ ok: false, json: async () => ({ error: "Ungültiger Zählerstand", field: "invoice_number_last" }) })
  await controller.update()
  assert.equal(controller.nextCounterTarget.textContent, "")
  date.value = ""
  await controller.update()
  assert.equal(controller.nextCounterTarget.textContent, "")
  date.value = "2026-10-08"
  respond = async () => { throw new Error("offline") }
  await controller.update()
  assert.equal(controller.nextCounterTarget.textContent, "Nächste fortlaufende Nummer: konnte nicht ermittelt werden")
})

test("preview shows a single linked abbreviation prompt and the number after input", async () => {
  const { controller } = await setup()
  controller.hasPreviewTarget = true
  controller.previewTarget = { replaceChildren(...children) { this.children = children } }
  controller.hasEditorStatusTarget = true
  controller.editorStatusTarget = { hidden: true }
  controller.hasEditorAbbreviationTarget = true
  controller.editorAbbreviationTarget = { id: "invoice-number-abbreviation-editor", value: "", setCustomValidity() {} }
  controller.editorAbbreviationFieldTarget = {}
  controller.formatTarget.value = "RE-[Jahr]-[Fortlaufendenummer]-[Kundenkürzel]"
  respond = async () => ({ ok: false, json: async () => ({ error: "Bitte ergänze das Kundenkürzel", field: "buyer_abbreviation", sequence: 1 }) })
  await controller.update()
  assert.equal(controller.previewTarget.children.map(child => child.textContent).join(""), "Bitte ergänze das Kundenkürzel")
  assert.equal(controller.previewTarget.children[1].href, "#invoice-number-abbreviation-editor")
  assert.equal(controller.editorStatusTarget.hidden, true)
  controller.abbreviationTarget.value = "MF"
  respond = async () => ({ ok: true, json: async () => ({ invoice_number: "RE-2026-0001-MF", sequence: 1 }) })
  await controller.update()
  assert.equal(controller.previewTarget.textContent, "RE-2026-0001-MF")
})


test("a counter cleared by the user stays empty during lookup and later form updates", async () => {
  const { controller } = await setup()
  controller.hasStartTarget = true
  controller.startTarget = { value: "147", setCustomValidity() {} }
  controller.hasNextCounterTarget = true
  controller.nextCounterTarget = {}
  respond = async () => ({ ok: true, json: async () => ({ invoice_number: "RE-2026-0148", sequence: 148 }) })
  await controller.update()
  controller.startTarget.value = ""
  respond = async () => ({ ok: true, json: async () => ({ invoice_number: "RE-2026-0001", sequence: 1 }) })
  await controller.update({ type: "input", target: controller.startTarget })
  assert.equal(controller.startTarget.value, "")
  assert.equal(controller.nextCounterTarget.textContent, "Nächste fortlaufende Nummer: 1")
  controller.abbreviationTarget.value = "MF"
  await controller.update()
  assert.equal(controller.startTarget.value, "")
  controller.startTarget.value = "1000"
  respond = async () => ({ ok: true, json: async () => ({ invoice_number: "RE-2026-1001", sequence: 1001 }) })
  await controller.update({ type: "input", target: controller.startTarget })
  assert.equal(controller.startTarget.value, "1000")
  assert.equal(controller.nextCounterTarget.textContent, "Nächste fortlaufende Nummer: 1001")
})

test("an in-flight automatic lookup cannot refill a counter cleared during the request", async () => {
  const { controller } = await setup()
  controller.hasStartTarget = true
  controller.startTarget = { value: "0", setCustomValidity() {} }
  controller.autoStart = "0"
  controller.key = null
  let finish
  respond = () => new Promise(resolve => { finish = resolve })
  const pending = controller.update()
  controller.startTarget.value = ""
  await controller.update({ type: "input", target: controller.startTarget })
  finish({ ok: true, json: async () => ({ invoice_number: "RE-2026-0001", sequence: 1 }) })
  await pending
  assert.equal(controller.startTarget.value, "")
})


test("changing invoice type refreshes the real number and all template examples", async () => {
  const { controller, kind } = await setup()
  const example = {}
  const format = "[Rechnungsart]-[Jahr]-[Fortlaufendenummer]"
  controller.formatTarget.value = format
  controller.presetTargets = [{ dataset: { format }, setAttribute() {}, querySelector: () => example }]
  for (const [value, code] of [["advance", "ANZ"], ["progress", "ABS"], ["final", "SR"], ["regular", "RE"]]) {
    kind.value = value
    kind.dataset.numberCode = code
    respond = async () => ({ ok: true, json: async () => ({ invoice_number: `${code}-2026-0042`, sequence: 42 }) })
    await controller.update()
    assert.equal(new URL(requests.at(-1).url, "http://localhost").searchParams.get("billing_kind"), value)
    assert.equal(controller.numberTarget.value, `${code}-2026-0042`)
    assert.equal(example.textContent, `${code}-2026-0001`)
  }
})

test("custom document format is marked immediately and resets with the global format", async () => {
  const { controller } = await setup()
  controller.hasGlobalFormatNoticeTarget = true
  controller.globalFormatNoticeTarget = {
    dataset: { globalFormat: "[Rechnungsart]-[Jahr]-[Fortlaufendenummer]", defaultNotice: "Globale Vorgabe", customNotice: "Angepasst" },
    classList: { toggle(name, active) { this.active = active } }
  }
  controller.formatTarget.value = "EIGEN-[Fortlaufendenummer]"
  controller.updateGlobalFormatNotice()
  assert.match(controller.globalFormatNoticeTarget.textContent, /^Angepasst /)
  assert.equal(controller.globalFormatNoticeTarget.classList.active, true)
  controller.formatTarget.value = controller.globalFormatNoticeTarget.dataset.globalFormat
  controller.updateGlobalFormatNotice()
  assert.equal(controller.globalFormatNoticeTarget.textContent, "Globale Vorgabe")
  assert.equal(controller.globalFormatNoticeTarget.classList.active, false)
})

test("invoice format flag distinguishes local override from a new global default", async () => {
  const { controller } = await setup()
  const once = { checked: false }
  controller.element.querySelector = () => once
  controller.hasCustomFormatFlagTarget = true
  controller.customFormatFlagTarget = { dataset: { globalFormat: "GLOBAL", localNotice: "Nur diese Rechnung", globalNotice: "Globale Vorgabe" } }
  controller.formatTarget.value = "EIGEN"
  controller.updateGlobalFormatNotice()
  assert.equal(controller.customFormatFlagTarget.hidden, false)
  assert.match(controller.customFormatFlagTarget.textContent, /^Globale Vorgabe\./)
  once.checked = true
  controller.updateGlobalFormatNotice()
  assert.match(controller.customFormatFlagTarget.textContent, /^Nur diese Rechnung\./)
  controller.formatTarget.value = "GLOBAL"
  controller.updateGlobalFormatNotice()
  assert.equal(controller.customFormatFlagTarget.hidden, true)
})

test("one-off format explanation appears only while the checkbox is checked", async () => {
  const { controller } = await setup()
  const once = { checked: false }
  controller.element.querySelector = () => once
  controller.hasOnceHintTarget = true
  controller.onceHintTarget = {}
  controller.updateGlobalFormatNotice()
  assert.equal(controller.onceHintTarget.hidden, true)
  once.checked = true
  controller.updateGlobalFormatNotice()
  assert.equal(controller.onceHintTarget.hidden, false)
})

test("format changes name added and removed placeholders, order, text and separators", async () => {
  const { controller } = await setup()
  const base = "[Kundenkürzel]-[Jahr]-[Monat]-[Tag]"
  assert.equal(controller.describeFormatChanges(base, `${base}-[Rechnungsart]`), "Rechnungsart hinzugefügt.")
  assert.equal(controller.describeFormatChanges(base, "[Jahr]-[Monat]-[Tag]"), "Kundenkürzel entfernt.")
  assert.equal(controller.describeFormatChanges("[Jahr]-[Monat]", "[Monat]-[Jahr]"), "Reihenfolge der Platzhalter geändert.")
  assert.equal(controller.describeFormatChanges("RE-[Jahr]", "ANZ-[Jahr]"), "Fester Text geändert.")
  assert.equal(controller.describeFormatChanges("[Jahr]-[Monat]", "[Jahr]/[Monat]"), "Trennzeichen geändert.")
  assert.equal(controller.describeFormatChanges("[Jahr]", "[Jahr][Jahr][Jahr]"), "Jahr (2×) hinzugefügt.")
  assert.equal(controller.describeFormatChanges(base, base), "")
})

test("reset restores the global format and notifies autosave without changing other fields", async () => {
  const { controller } = await setup()
  controller.hasCustomFormatFlagTarget = true
  controller.customFormatFlagTarget = { dataset: { globalFormat: "[Rechnungsart]-[Jahr]" } }
  controller.formatTarget.value = "EIGEN"
  controller.abbreviationTarget.value = "KUNDE"
  const events = []
  controller.formatTarget.dispatchEvent = event => events.push(event.type)
  controller.formatTarget.focus = () => { controller.focused = true }
  controller.resetFormat({ preventDefault() {} })
  assert.equal(controller.formatTarget.value, "[Rechnungsart]-[Jahr]")
  assert.equal(controller.abbreviationTarget.value, "KUNDE")
  assert.deepEqual(events, ["input"])
  assert.equal(controller.focused, true)
})

test("selecting template text does not apply the template while keyboard activation still works", async () => {
  const { controller } = await setup()
  const before = controller.formatTarget.value
  const template = { dataset: { format: "NEU-[Jahr]" }, ownerDocument: { getSelection: () => ({ isCollapsed: false, containsNode: () => true }) } }
  let prevented = false
  controller.preset({ currentTarget: template, detail: 1, preventDefault() { prevented = true } })
  assert.equal(controller.formatTarget.value, before)
  assert.equal(prevented, true)
  controller.formatTarget.dispatchEvent = () => {}
  controller.preset({ currentTarget: template, detail: 0 })
  assert.equal(controller.formatTarget.value, "NEU-[Jahr]")
})

test("template cards support Enter and Space and leave other keys alone", async () => {
  const { controller } = await setup()
  const card = { dataset: { format: "NEU-[Jahr]" } }
  let changes = 0
  controller.formatTarget.dispatchEvent = () => changes++
  controller.preset({ type: "keydown", key: "Tab", currentTarget: card })
  assert.equal(changes, 0)
  for (const key of ["Enter", " "]) {
    let prevented = false
    controller.preset({ type: "keydown", key, currentTarget: card, preventDefault() { prevented = true } })
    assert.equal(prevented, true)
    assert.equal(controller.formatTarget.value, "NEU-[Jahr]")
  }
  assert.equal(changes, 2)
})
