import { readFileSync } from "node:fs"
import { runInNewContext } from "node:vm"
import test from "node:test"
import assert from "node:assert/strict"

const source = readFileSync(new URL("../../app/javascript/controllers/order_billing_controller.js", import.meta.url), "utf8")
const prices = readFileSync(new URL("../../app/javascript/price_input.js", import.meta.url), "utf8").replaceAll("export ", "")
const Controller = runInNewContext(prices + "\n" + source.replace(/^import .*\n/gm, "").replace("export default class", "globalThis.OrderBilling = class") + "\nOrderBilling", { Controller: class {} })

test("half-cent amounts round like the server without floating point losing a cent", () => {
  const controller = new Controller()
  assert.equal(controller.roundMoney(0.29 * 50 / 100), 0.15)
  assert.equal(controller.roundMoney(0.03 * 50 / 100), 0.02)
  assert.equal(controller.roundMoney(0.01 * 50 / 100), 0.01)
  assert.equal(controller.roundMoney(10.01 * 33.33 / 100), 3.34)
})

test("position keys remain stable when another position is removed", () => {
  const controller = new Controller()
  controller.linkedValue = false
  const row = (key, description, quantity, price) => ({ querySelector: selector => {
    if (selector.includes("description")) return { name: `invoice[invoice_lines_attributes][${key}][description]`, value: description }
    if (selector.includes("quantity")) return { value: quantity }
    if (selector.includes("unit_price")) return { value: price }
    return { value: "HUR" }
  } })
  const first = row("17", "Material", "1", "300,00")
  const second = row("42", "Umsetzung", "2", "250,00")
  controller.element = { querySelectorAll: () => [first, second] }
  assert.deepEqual(Array.from(controller.positions(), line => [line.key, line.total]), [["17", 300], ["42", 500]])
  controller.element.querySelectorAll = () => [second]
  assert.deepEqual(Array.from(controller.positions(), line => [line.key, line.total]), [["42", 500]])
})
