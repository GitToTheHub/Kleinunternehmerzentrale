import { readFileSync } from "node:fs"
import { runInNewContext } from "node:vm"
import test from "node:test"
import assert from "node:assert/strict"

const source = readFileSync(new URL("../../app/javascript/controllers/field_calculator_controller.js", import.meta.url), "utf8")
const calculate = runInNewContext(source.replace(/^import .*\n/gm, "").replace("export function", "function").replace("export default class", "class Calculator") + "\ncalculateExpression", { Controller: class {} })
const suggestion = runInNewContext(source.replace(/^import .*\n/gm, "").replace("export function", "function").replace("export default class", "class Calculator") + "\ntimeRateSuggestion", { Controller: class {} })

test("unparenthesized time sums with a rate offer explicit grouping", () => {
  assert.equal(suggestion("20 min + 20 min * 40 Euro"), "(20 min + 20 min) × 40 Euro")
  assert.equal(suggestion("20 min + 1,5std. + 1:30 × 60 €"), "(20 min + 1,5std. + 1:30) × 60 €")
  assert.equal(suggestion("(20 min + 20 min) * 40 Euro"), null)
  assert.equal(suggestion("20 Euro + 20 Euro * 40"), null)
  assert.equal(suggestion("20 min * 40 Euro + 20 min * 50 Euro"), null)
})

test("arithmetic follows precedence and supports German decimals and parentheses", () => {
  assert.equal(calculate("2 + 3 * 4"), 14)
  assert.equal(calculate("(2 + 3) × 4"), 20)
  assert.equal(calculate("10,5 ÷ 2 − 1"), 4.25)
  assert.equal(calculate("-2 + +3"), 1)
})

test("times add as decimal hours and can be multiplied by a rate", () => {
  assert.ok(Math.abs(calculate("20 min + 20 min + 1,5 Std + 1:30") - 220 / 60) < 1e-10)
  assert.equal(calculate("(20 min + 20 min + 1,5 Std. + 1:30) * 60"), 220)
  assert.equal(calculate("1 h + 30 Minuten"), 1.5)
})

test("Euro amounts accept currency words and symbols", () => {
  assert.equal(calculate("20 Euro"), 20)
  assert.equal(calculate("20 Euro + 15 € + 2,50 EUR"), 37.5)
  assert.equal(calculate("20Euro + 5€"), 25)
  assert.equal(calculate("(30 min + 1 Std) * 60 Euro"), 90)
})

test("price calculations distinguish hours from amounts", () => {
  assert.equal(calculate("20 min + 20 min", { withUnit: true, price: true }).unit, "time")
  assert.equal(calculate("(20 min + 20 min) / 2", { withUnit: true, price: true }).unit, "time")
  assert.equal(calculate("(20 min + 20 min) * 60", { withUnit: true, price: true }).unit, "money")
  assert.equal(calculate("(20 min + 20 min) * 60 Euro", { withUnit: true, price: true }).unit, "money")
  assert.equal(calculate("20 Euro + 15 €", { withUnit: true, price: true }).unit, "money")
  assert.throws(() => calculate("20 min + 20 Euro", { withUnit: true, price: true }), /nicht direkt addiert/)
})

test("invalid expressions cannot become field values or executable code", () => {
  for (const text of ["", "1:75", "1 / 0", "2 +", "(2 + 3", "2 3", "14.08.26", "alert(1)", "2 ** 3"]) {
    assert.throws(() => calculate(text), undefined, text)
  }
})
