import { readFileSync } from "node:fs"
import { runInNewContext } from "node:vm"
import test from "node:test"
import assert from "node:assert/strict"

const source = readFileSync(new URL("../../app/javascript/controllers/settlement_selection_controller.js", import.meta.url), "utf8")
const Selection = runInNewContext(source.replace(/^import .*\n/, "").replace("export default class", "globalThis.Selection = class") + "\nSelection", { Controller: class {}, Event })

test("only the selected customer's advances are submitted and customer changes clear incompatible choices", () => {
  const controller = new Selection()
  const kind = { value: "final" }
  const customer = { value: "1" }
  const inputs = [{ checked: true }, { checked: true }]
  const rows = inputs.map((input, index) => ({ dataset: { customerId: String(index + 1), amount: "300" }, querySelector: () => input }))
  let changes = 0
  controller.element = { closest: () => ({ querySelector: query => query.includes("billing_kind") ? kind : customer }), dispatchEvent() { changes++ } }
  controller.rowTargets = rows
  controller.hintTarget = {}
  controller.sumTarget = {}
  controller.update()
  assert.equal(inputs[0].disabled, false)
  assert.equal(inputs[1].disabled, true)
  assert.equal(inputs[1].checked, false)
  assert.match(controller.sumTarget.textContent, /300,00/)
  customer.value = "2"
  controller.update()
  assert.equal(inputs[0].checked, false)
  assert.equal(inputs[1].disabled, false)
  assert.equal(changes, 2)
  kind.value = "regular"
  controller.update()
  assert.equal(controller.element.hidden, true)
  assert.equal(inputs[1].disabled, true)
})
