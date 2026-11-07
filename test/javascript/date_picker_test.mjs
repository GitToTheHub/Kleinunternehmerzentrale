import { readFileSync } from "node:fs"
import { runInNewContext } from "node:vm"
import test from "node:test"
import assert from "node:assert/strict"

const source = readFileSync(new URL("../../app/javascript/controllers/date_picker_controller.js", import.meta.url), "utf8")
const fields = {}
let footer = null
const viewportWindow = { innerWidth: 1024, innerHeight: 800, matchMedia: () => ({ matches: false }), scrollBy() {} }
const Picker = runInNewContext(source.replace(/^import .*\n/, "").replace("export default class", "globalThis.Picker = class") + "\nPicker", {
  Controller: class {}, Date, Event, window: viewportWindow,
  document: { querySelector: () => footer, getElementById: id => fields[id], createElement: (tagName) => ({ tagName, attributes: {}, setAttribute(name, value) { this.attributes[name] = value }, addEventListener() {} }) },
})

function picker(value) {
  const controller = new Picker()
  controller.inputTarget = { type: "hidden", value, events: [], dispatchEvent(event) { this.events.push(event.type) } }
  controller.textInput = { setAttribute(name, value) { this[name] = value }, type: "text", value: "", setCustomValidity(message) { this.validationMessage = message }, focus() { this.focused = true } }
  controller.textInput.getBoundingClientRect = () => ({ top: 100, bottom: 144, left: 100 })
  controller.element = { getBoundingClientRect: () => ({ top: 100, bottom: 144, left: 100 }) }
  controller.calendarTarget = { hidden: true, contains: () => true, style: {}, getBoundingClientRect: () => ({ width: 360, height: 350 }) }
  controller.monthTarget = {}
  controller.todayButtonTarget = {}
  controller.daysTarget = { replaceChildren(...cells) { this.cells = cells }, querySelector() { return null } }
  controller.dispatch = () => {}
  return controller
}

test("calendar supports leap years, Monday first and year navigation", () => {
  const controller = picker("2028-02-29")
  controller.open()
  assert.equal(controller.daysTarget.cells[0].tagName, "span")
  assert.equal(controller.daysTarget.cells.length, 30)
  assert.equal(controller.daysTarget.cells.at(-1).attributes["aria-pressed"], "true")
  controller.visibleMonth = new Date(2026, 11, 1)
  controller.next()
  assert.equal(controller.iso(controller.visibleMonth), "2027-01-01")
})

test("calendar selection fills editable German text, stores ISO dates and notifies autosave", () => {
  const controller = picker("2026-10-07")
  controller.open()
  controller.select("2026-10-21")
  assert.equal(controller.textInput.type, "text")
  assert.equal(controller.textInput.value, "21.10.2026")
  assert.equal(controller.inputTarget.value, "2026-10-21")
  assert.deepEqual(controller.inputTarget.events, ["input", "change"])
  assert.equal(controller.calendarTarget.hidden, true)
  assert.equal(controller.textInput.focused, true)
})

test("calendar respects disabled fields and date limits", () => {
  const controller = picker("2026-10-07")
  controller.inputTarget.disabled = true
  controller.open()
  assert.equal(controller.calendarTarget.hidden, true)
  controller.inputTarget.max = "2026-10-31"
  controller.select("2026-11-01")
  assert.equal(controller.inputTarget.value, "2026-10-07")
})

test("manual editing accepts valid dates and rejects impossible dates", () => {
  const controller = picker("2026-10-07")
  controller.textInput.value = "9.11.2026"
  controller.update({ target: controller.textInput })
  assert.equal(controller.inputTarget.value, "2026-11-09")
  assert.equal(controller.textInput.validationMessage, "")
  controller.textInput.value = "31.02.2026"
  controller.update({ target: controller.textInput })
  assert.equal(controller.inputTarget.value, "")
  assert.match(controller.textInput.validationMessage, /gültiges Datum/)
  assert.equal(controller.parse("29.02.2028"), "2028-02-29")
  assert.equal(controller.parse("29.02.2026"), "")
})

test("required and disabled states transfer to the editable input", () => {
  const controller = picker("")
  controller.inputTarget.required = true
  controller.syncConstraints()
  assert.equal(controller.textInput.required, true)
  controller.inputTarget.required = false
  controller.inputTarget.disabled = true
  controller.syncConstraints()
  assert.equal(controller.textInput.required, false)
  assert.equal(controller.textInput.disabled, true)
  assert.equal(controller.textInput.disabled, true)
})

test("payment deadline is validated against changed invoice dates and can be corrected", () => {
  const controller = picker("2026-10-07")
  controller.minDateFieldValue = "invoice_issued_on"
  controller.minErrorValue = "Die Zahlungsfrist darf nicht vor dem Rechnungsdatum liegen."
  fields.invoice_issued_on = { value: "2026-10-06" }
  controller.syncDisplay()
  controller.syncMinimum()
  assert.equal(controller.textInput.validationMessage, "")

  fields.invoice_issued_on.value = "2026-10-08"
  controller.syncMinimum()
  assert.equal(controller.textInput.validationMessage, controller.minErrorValue)
  controller.textInput.value = "08.10.2026"
  controller.update({ target: controller.textInput })
  assert.equal(controller.textInput.validationMessage, "")
  controller.textInput.value = "07.10.2026"
  controller.update({ target: controller.textInput })
  assert.equal(controller.textInput.validationMessage, controller.minErrorValue)
  fields.invoice_issued_on.value = "2026-10-07"
  controller.syncMinimum()
  assert.equal(controller.textInput.validationMessage, "")
  controller.inputTarget.disabled = true
  controller.syncConstraints()
  assert.equal(controller.textInput.disabled, true)
})


test("opening a low field scrolls the page and keeps the calendar below it", () => {
  const controller = picker("2026-10-11")
  footer = { getBoundingClientRect: () => ({ top: 700, bottom: 800 }) }
  let scrolled = 0
  viewportWindow.scrollBy = ({ top, behavior }) => { assert.equal(behavior, "smooth"); scrolled += top }
  controller.textInput.getBoundingClientRect = () => ({ top: 620 - scrolled, bottom: 664 - scrolled, left: 100 })
  controller.open()
  assert.equal(scrolled, 330)
  assert.ok(664 - scrolled + 8 + 350 <= 692)
  footer = null
})

test("small viewports keep the field visible without limiting calendar height", () => {
  const controller = picker("2026-10-11")
  viewportWindow.innerWidth = 400
  viewportWindow.innerHeight = 300
  let scrolled = 0
  viewportWindow.scrollBy = ({ top, behavior }) => { assert.equal(behavior, "smooth"); scrolled += top }
  controller.textInput.getBoundingClientRect = () => ({ top: 150 - scrolled, bottom: 194 - scrolled, left: 300 })
  controller.open()
  assert.equal(scrolled, 142)
  assert.equal(controller.calendarTarget.style.maxHeight, undefined)
  assert.equal(controller.calendarTarget.style.left, "-268px")
  viewportWindow.innerWidth = 1024
  viewportWindow.innerHeight = 800
  viewportWindow.scrollBy = () => {}
})


test("automatic scrolling respects reduced motion", () => {
  const controller = picker("2026-10-11")
  viewportWindow.matchMedia = () => ({ matches: true })
  let behavior
  viewportWindow.scrollBy = options => { behavior = options.behavior }
  controller.textInput.getBoundingClientRect = () => ({ top: 620, bottom: 664, left: 100 })
  controller.open()
  assert.equal(behavior, "instant")
  viewportWindow.matchMedia = () => ({ matches: false })
  viewportWindow.scrollBy = () => {}
})


test("an empty end date opens on the day after the start, including month and year boundaries", () => {
  for (const [start, expected] of [["2026-11-01", "2026-11-02"], ["2026-10-31", "2026-11-01"], ["2026-12-31", "2027-01-01"], ["2028-02-28", "2028-02-29"]]) {
    const controller = picker("")
    controller.minDateFieldValue = "start"
    controller.minExclusiveValue = true
    fields.start = { value: start }
    controller.open()
    assert.equal(controller.focusDate, expected)
    assert.equal(controller.iso(controller.visibleMonth), `${expected.slice(0, 7)}-01`)
    assert.equal(controller.inputTarget.value, "")
    assert.equal(controller.inputTarget.min, expected)
    controller.select(start)
    assert.equal(controller.inputTarget.value, "")
    controller.select(expected)
    assert.equal(controller.inputTarget.value, expected)
  }
  delete fields.start
})

test("an existing end date is kept and remains the initial calendar date", () => {
  const controller = picker("2026-11-20")
  controller.minDateFieldValue = "start"
  controller.minExclusiveValue = true
  fields.start = { value: "2026-11-01" }
  controller.open()
  assert.equal(controller.focusDate, "2026-11-20")
  assert.equal(controller.inputTarget.value, "2026-11-20")
  controller.syncDisplay()
  fields.start.value = "2026-12-01"
  controller.open()
  assert.equal(controller.iso(controller.visibleMonth), "2026-12-01")
  assert.equal(controller.inputTarget.value, "2026-11-20")
  assert.match(controller.textInput.validationMessage, /gültiges Datum/)
  delete fields.start
})


test("an exclusive end date disables and rejects the start day, including manual input", () => {
  const controller = picker("")
  controller.minDateFieldValue = "start"
  controller.minExclusiveValue = true
  fields.start = { value: "2026-11-01" }
  controller.open()
  assert.equal(controller.daysTarget.cells.find(cell => cell.attributes?.["data-date"] === "2026-11-01").disabled, true)
  assert.equal(controller.daysTarget.cells.find(cell => cell.attributes?.["data-date"] === "2026-11-02").disabled, false)
  controller.textInput.value = "01.11.2026"
  controller.update({ target: controller.textInput })
  assert.match(controller.textInput.validationMessage, /gültiges Datum/)
  controller.textInput.value = "02.11.2026"
  controller.update({ target: controller.textInput })
  assert.equal(controller.textInput.validationMessage, "")
  delete fields.start
})


test("Today follows the same allowed range as calendar days and updates when the start changes", () => {
  const controller = picker("")
  const today = new Date()
  const yesterday = new Date(today)
  yesterday.setDate(today.getDate() - 1)
  controller.minDateFieldValue = "start"
  controller.minExclusiveValue = true
  fields.start = { value: controller.iso(today) }
  controller.open()
  assert.equal(controller.todayButtonTarget.disabled, true)
  controller.today()
  assert.equal(controller.inputTarget.value, "")
  fields.start.value = controller.iso(yesterday)
  controller.syncMinimum()
  assert.equal(controller.todayButtonTarget.disabled, false)
  controller.today()
  assert.equal(controller.inputTarget.value, controller.iso(today))
  delete fields.start
})

test("Today is also disabled when beyond the maximum date", () => {
  const controller = picker("")
  const yesterday = new Date()
  yesterday.setDate(yesterday.getDate() - 1)
  controller.inputTarget.max = controller.iso(yesterday)
  controller.open()
  assert.equal(controller.todayButtonTarget.disabled, true)
})


test("typing opens the calendar without replacing partial text and follows complete dates", () => {
  const controller = picker("2026-10-07")
  controller.textInput.value = "12."
  controller.update({ target: controller.textInput, type: "input" })
  assert.equal(controller.calendarTarget.hidden, false)
  assert.equal(controller.textInput.value, "12.")
  assert.equal(controller.inputTarget.value, "")
  controller.textInput.value = "12.11.2026"
  controller.update({ target: controller.textInput, type: "input" })
  assert.equal(controller.iso(controller.visibleMonth), "2026-11-01")
  assert.equal(controller.inputTarget.value, "2026-11-12")
  controller.close()
  controller.update({ target: controller.textInput, type: "change" })
  assert.equal(controller.calendarTarget.hidden, true)
})


test("dates without a year use the current year and adjacent years at the year boundary", () => {
  const controller = picker("")
  const november = new Date(2026, 10, 7)
  const december = new Date(2026, 11, 15)
  const january = new Date(2027, 0, 15)
  assert.equal(controller.parse("21.10.", november), "2026-10-21")
  assert.equal(controller.parse("21.10", november), "2026-10-21")
  assert.equal(controller.parse("10.01", december), "2027-01-10")
  assert.equal(controller.parse("10.12.", january), "2026-12-10")
  assert.equal(controller.parse("10.02.", december), "2026-02-10")
  assert.equal(controller.parse("10.11.", january), "2027-11-10")
  assert.equal(controller.parse("10.01.2025", december), "2025-01-10")
  assert.equal(controller.parse("10.12.2028", january), "2028-12-10")
  assert.equal(controller.parse("29.02.", new Date(2028, 1, 1)), "2028-02-29")
  for (const text of ["29.02.", "31.04.", "10.13.", "21.", "21.10.2", "21.10.26"]) {
    assert.equal(controller.parse(text, november), "", text)
  }
})


test("a typed day is highlighted in the visible month without storing an incomplete date", () => {
  const controller = picker("2026-10-07")
  controller.open()
  const selected = () => controller.daysTarget.cells.filter(cell => cell.attributes?.["aria-pressed"] === "true")
  for (const text of ["2", "21", "21."]) {
    controller.textInput.value = text
    controller.update({ target: controller.textInput, type: "input" })
    const day = text.replace(".", "").padStart(2, "0")
    assert.equal(selected()[0].attributes["data-date"], `2026-10-${day}`)
    assert.equal(controller.inputTarget.value, "")
    assert.equal(controller.textInput.value, text)
  }
  controller.next()
  assert.equal(selected()[0].attributes["data-date"], "2026-11-21")
  for (const text of ["0", "32", "31", "", "21.13."]) {
    controller.textInput.value = text
    controller.update({ target: controller.textInput, type: "input" })
    assert.equal(selected().length, 0, text)
  }
  controller.inputTarget.min = "2026-11-22"
  controller.textInput.value = "21"
  controller.update({ target: controller.textInput, type: "input" })
  assert.equal(selected().length, 0)
})


test("leaving the date field closes the calendar but focusing its days keeps it open", () => {
  const controller = picker("2026-10-21")
  const day = {}
  controller.element.contains = target => target === day
  controller.open()
  controller.focusout({ relatedTarget: day })
  assert.equal(controller.calendarTarget.hidden, false)
  controller.focusout({ relatedTarget: {} })
  assert.equal(controller.calendarTarget.hidden, true)
})


test("the calendar in a payment dialog keeps the submit actions accessible", () => {
  const controller = picker("2026-10-21")
  controller.inDialog = true
  controller.calendarTarget.hidden = false
  controller.element.closest = () => ({ querySelector: () => ({ getBoundingClientRect: () => ({ top: 600, bottom: 650 }) }) })
  controller.textInput.getBoundingClientRect = () => ({ top: 400, bottom: 444, left: 100 })
  controller.position()
  assert.ok(parseFloat(controller.calendarTarget.style.top) + 350 < 600)
})
