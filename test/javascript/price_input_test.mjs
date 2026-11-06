import { readFileSync } from "node:fs"
import { runInNewContext } from "node:vm"
import test from "node:test"
import assert from "node:assert/strict"

const source = readFileSync(new URL("../../app/javascript/price_input.js", import.meta.url), "utf8").replaceAll("export function", "function")
const { parsePrice, formatPrice } = runInNewContext(source + "\n({ parsePrice, formatPrice })")

test("prices retain cents and display German decimal notation", () => {
  for (const input of ["50,50", "50.50", " 50,50 "]) assert.equal(parsePrice(input), 50.5)
  assert.equal(parsePrice("1.234,56"), 1234.56)
  assert.equal(formatPrice("50"), "50,00")
  assert.equal(formatPrice("50.5"), "50,50")
  assert.equal(formatPrice(""), "")
})

test("malformed prices are not truncated or rounded into valid values", () => {
  for (const input of ["1.234", "50,555", "50abc", "1e3", "-5", "1..234,56"]) {
    assert.ok(Number.isNaN(parsePrice(input)), input)
    assert.equal(formatPrice(input), input)
  }
})
