import { readFileSync } from "node:fs"
import { runInNewContext } from "node:vm"
import test from "node:test"
import assert from "node:assert/strict"
const source = readFileSync(new URL("../../app/javascript/controllers/bookkeeping_import_controller.js", import.meta.url), "utf8")
const display = {}
const Import = runInNewContext(source.replace(/^import .*\n/gm, "").replace("export default class", "globalThis.Import = class") + "\nImport", { Controller: class {}, document: { getElementById: () => display } })

test("PDF mode reads date and year from the file and manual mode preserves entered amounts", () => {
  const c = new Import()
  for (const target of ["csv", "manual", "file", "fileLabel", "csvHelp", "pdfHelp", "template", "cutoff", "source", "sumError", "totals"]) c[`${target}Target`] = {}
  c.modeTarget = { value: "pdf" }
  c.yearTarget = { value: "2026" }
  c.positionTargets = c.captionTargets = c.amountTargets = c.sumTargets = c.sourceNoteTargets = []
  const input = { value: "12,34" }
  c.rowTargets = [{ dataset: { years: "2026" }, querySelectorAll: () => [input] }]
  c.connect()
  assert.equal(c.fileTarget.accept, ".pdf,application/pdf")
  assert.equal(c.fileTarget.required, true)
  assert.equal(c.sourceTarget.required, false)
  assert.equal(c.cutoffTarget.required, false)
  assert.equal(display.required, false)
  assert.equal(c.yearTarget.disabled, true)
  assert.equal(input.disabled, true)
  c.modeTarget.value = "manual"
  c.update()
  assert.equal(c.fileTarget.disabled, true)
  assert.equal(c.sourceTarget.required, true)
  assert.equal(display.required, true)
  assert.equal(c.yearTarget.disabled, false)
  assert.equal(input.disabled, false)
  assert.equal(input.value, "12,34")
  c.yearTarget.value = "2025"
  c.updateReferences()
  assert.equal(input.disabled, true)
  assert.equal(c.rowTargets[0].hidden, true)
  c.modeTarget.value = "csv"
  c.update()
  assert.equal(c.fileTarget.accept, ".csv,text/csv")
})

test("live totals use cents and exclude informational amounts while counting reserves once", () => {
  const c = new Import()
  const field = (key, effect, value, section = "25", disabled = false) => ({ value, disabled, dataset: { key, effect, section } })
  c.modeTarget = { value: "manual" }
  c.sumErrorTarget = {}
  c.totalsTarget = {}
  c.amountTargets = [
    field("income_small", "income", "1.000,10", "20"),
    field("income_small_details", "info", "300", "20"),
    field("expense_goods", "expense", "0,10"), field("expense_other", "expense", "0,20"),
    field("expense_disallowed", "expense_reduction", "0,10"),
    field("reserve_create", "expense", "10", "27"), field("reserve_release", "income", "5", "27"),
    field("iab_deduction", "profit_minus", "20"), field("method_change", "profit_plus", "-2"),
    field("deposits", "info", "200", "29"), field("withdrawals", "info", "300", "29"),
    field("expense_livestock_reserve", "expense", "999", "25", true)
  ]
  const keys = ["income", "expenses", "surplus", "corrections", "reserveCreate", "reserveRelease", "deposits", "withdrawals"]
  c.sumTargets = keys.map(key => ({ dataset: { key } }))
  c.updateTotals()
  const result = Object.fromEntries(c.sumTargets.map(item => [item.dataset.key, item.textContent.replace(/\s/g, " ")]))
  assert.equal(result.income, "1.005,10 €")
  assert.equal(result.expenses, "10,20 €")
  assert.equal(result.corrections, "-22,00 €")
  assert.equal(result.surplus, "972,90 €")
  assert.equal(result.reserveCreate, "10,00 €")
  assert.equal(result.reserveRelease, "5,00 €")
  assert.equal(result.deposits, "200,00 €")
  assert.equal(result.withdrawals, "300,00 €")
  c.amountTargets[0].value = "1,234"
  c.updateTotals()
  assert.equal(c.sumTargets[0].textContent, "–")
  assert.equal(c.sumErrorTarget.hidden, false)
  c.amountTargets[0].value = "1000.10"
  c.updateTotals()
  assert.equal(c.sumErrorTarget.hidden, true)
  assert.equal(c.parseCents("0,01"), 1)
  assert.equal(c.parseCents("-1.234,56 €"), -123456)
  assert.equal(c.parseCents("1.234"), null)
  assert.equal(c.parseCents("10000000000"), null)
})
