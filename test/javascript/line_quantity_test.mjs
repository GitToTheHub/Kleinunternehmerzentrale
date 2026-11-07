import { readFileSync } from "node:fs"
import { runInNewContext } from "node:vm"
import test from "node:test"
import assert from "node:assert/strict"

const source = readFileSync(new URL("../../app/javascript/controllers/line_quantity_controller.js", import.meta.url), "utf8")
const convert = runInNewContext(source.replace(/^import .*\n/gm, "").replace("export function", "function").replace("export default class", "class Quantity") + "\nconvertHourlyPrice", { Controller: class {} })

test("hours and flat prices preserve the total and use the position rate", () => {
  const flat = convert(3.1, 50, true)
  assert.equal(flat.quantity, 1)
  assert.equal(flat.price, 155)
  const hourly = convert(1, 155, false, 50)
  assert.equal(hourly.quantity, 3.1)
  assert.equal(hourly.price, 50)
  assert.equal(hourly.difference, 0)
  assert.equal(convert(1, 200, false, 50).quantity, 4)
  assert.equal(convert(1, 200, false, 80).quantity, 2.5)
})

test("cent rounding and three decimal hours expose any changed total", () => {
  assert.equal(convert(1.005, 1, true).price, 1.01)
  const hourly = convert(1, 55, false, 95)
  assert.equal(hourly.quantity, 0.579)
  assert.equal(hourly.difference, 0.01)
})

test("invalid or unavailable rates and quantities cannot silently change amounts", () => {
  for (const rate of [0, -1, NaN, Infinity]) {
    assert.throws(() => convert(1, 155, false, rate), /Stundensatz/)
  }
  for (const quantity of [NaN, 0, -1, 1e10]) {
    assert.throws(() => convert(quantity, 50, true), /Stunden/)
  }
  assert.throws(() => convert(1, NaN, true), /Preis/)
  for (const rate of [0, 50, NaN]) {
    const empty = convert(1, 0, false, rate)
    assert.equal(empty.quantity, 1)
    assert.equal(empty.price, 0)
    assert.equal(empty.difference, 0)
  }
  assert.equal(convert(3.1, 0, true).price, 0)
})
