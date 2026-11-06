import { readFileSync } from "node:fs"
import { runInNewContext } from "node:vm"
import test from "node:test"
import assert from "node:assert/strict"

const source = readFileSync(new URL("../../app/javascript/controllers/imprint_lookup_controller.js", import.meta.url), "utf8")
let finishRequest
let requests = 0
const inputs = {}
const ImprintLookup = runInNewContext(source.replace(/^import .*\n/, "").replace("export default class", "globalThis.ImprintLookup = class") + "\nImprintLookup", {
  Controller: class {}, AbortController,
  Event,
  document: { querySelector: () => ({ content: "csrf" }), getElementById: (id) => inputs[id] },
  fetch: () => { requests++; return new Promise((resolve) => { finishRequest = resolve }) },
})

test("applying customer data updates customer fields and notifies autosave", () => {
  const controller = new ImprintLookup()
  const events = []
  inputs.invoice_buyer_name = { tagName: "INPUT", value: "", dispatchEvent(event) { events.push(event.type) } }
  controller.statusTarget = {}

  controller.apply([["buyer_name", "Beispiel GmbH"]])

  assert.equal(inputs.invoice_buyer_name.value, "Beispiel GmbH")
  assert.deepEqual(events, ["input", "change"])
})

test("Enter immediately shows loading feedback, blocks duplicate requests and resets after failure", async () => {
  const controller = new ImprintLookup()
  controller.domainTarget = { value: "example.org" }
  controller.panelTarget = { setAttribute() {} }
  controller.statusTarget = { dataset: {}, removeAttribute() {} }
  controller.buttonTarget = {}
  controller.buttonLabelTarget = {}
  controller.spinnerTarget = {}
  let prevented = false
  controller.submitOnEnter({ key: "Enter", preventDefault() { prevented = true } })
  assert.equal(prevented, true)
  assert.equal(controller.buttonTarget.disabled, true)
  assert.equal(controller.spinnerTarget.hidden, false)
  assert.equal(controller.buttonLabelTarget.textContent, "Daten werden ermittelt …")
  await controller.lookup()
  assert.equal(requests, 1)

  finishRequest({ ok: false, json: async () => ({ error: "Nicht erreichbar" }) })
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(controller.buttonTarget.disabled, false)
  assert.equal(controller.domainTarget.readOnly, false)
  assert.equal(controller.spinnerTarget.hidden, true)
  assert.equal(controller.buttonLabelTarget.textContent, "Daten ermitteln")
  assert.equal(controller.statusTarget.textContent, "Nicht erreichbar")
})

test("a lookup finishing after leaving the form cannot fill a different invoice", async () => {
  const controller = new ImprintLookup()
  controller.domainTarget = { value: "example.org" }
  controller.panelTarget = { setAttribute() {} }
  controller.statusTarget = { dataset: {}, removeAttribute() {} }
  controller.buttonTarget = {}
  controller.buttonLabelTarget = {}
  controller.spinnerTarget = {}
  let applied = false
  controller.apply = () => { applied = true }
  const lookup = controller.lookup()
  controller.disconnect()
  assert.equal(controller.request.signal.aborted, true)
  finishRequest({ ok: true, json: async () => ({ buyer_name: "Late result" }) })
  await lookup
  assert.equal(applied, false)
  assert.equal(controller.loading, false)
})


test("successful lookup stages recognized data until explicitly accepted", async () => {
  const controller = new ImprintLookup()
  controller.domainTarget = { value: "example.org" }
  controller.panelTarget = { setAttribute() {} }
  controller.statusTarget = { dataset: {}, removeAttribute() {} }
  controller.buttonTarget = {}
  controller.buttonLabelTarget = {}
  controller.spinnerTarget = {}
  controller.resultsTarget = { hidden: true }
  controller.hasResultsTarget = true
  let staged
  let applied
  let closed = false
  controller.renderResult = entries => { staged = entries; controller.resultsTarget.hidden = false }
  controller.apply = entries => { applied = entries }
  controller.popoverTarget = { hidePopover() { closed = true } }
  const lookup = controller.lookup()
  finishRequest({ ok: true, json: async () => ({ buyer_name: "Firma", buyer_email: "", unknown: "ignored" }) })
  await lookup
  assert.deepEqual(JSON.parse(JSON.stringify(staged)), [["buyer_name", "Firma"]])
  assert.equal(applied, undefined)
  assert.equal(closed, false)
  controller.accept()
  assert.equal(applied, staged)
  assert.equal(closed, true)
  assert.equal(controller.resultsTarget.hidden, true)
  assert.equal(controller.entries, null)
})

test("changing the website discards previously staged data", () => {
  const controller = new ImprintLookup()
  controller.entries = [["buyer_name", "Old result"]]
  controller.resultsTarget = { hidden: false }
  controller.hasResultsTarget = true
  controller.statusTarget = { removeAttribute() {} }
  controller.resetResult()
  assert.equal(controller.resultsTarget.hidden, true)
  assert.equal(controller.entries, null)
  let applied = false
  controller.apply = () => { applied = true }
  controller.accept()
  assert.equal(applied, false)
})
