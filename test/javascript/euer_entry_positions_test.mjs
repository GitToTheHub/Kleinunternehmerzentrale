import { readFileSync } from "node:fs"
import { runInNewContext } from "node:vm"
import test from "node:test"
import assert from "node:assert/strict"
const source = readFileSync(new URL("../../app/javascript/controllers/euer_entry_controller.js", import.meta.url), "utf8")
const Entry = runInNewContext(source.replace(/^import .*\n/gm, "").replace("export default class", "globalThis.Entry = class") + "\nEntry", {
  Controller: class {}, Option: class { constructor(text, value) { this.textContent = text; this.value = value } }
})
const option = (value, label, group, example) => ({ value, textContent: label, dataset: { label, kinds: "expense", expenseGroup: group, example }, cloneNode() { return { ...this, dataset: { ...this.dataset } } } })
function setup(selected = "") {
  const c = new Entry()
  c.kindTargets = [{ checked: true, value: "expense", dataset: { dateLabel: "Zahlungsdatum", categoryLabel: "Ausgabenart" } }]
  c.categoryOptions = [option("expense_it", "Laufende EDV-Kosten", "Telefon und EDV", "Hosting"), option("expense_phone", "Telekommunikation", "Telefon und EDV", "Mobilfunk"), option("expense_goods", "Waren", "Handel", "Handelsware")]
  c.categoryTarget = { value: selected, replaceChildren(...options) { this.options = options }, focus() {} }
  for (const name of ["fields", "dateLabel", "categoryLabel", "expenseField", "expenseGroupField", "categoryChoice", "expenseExample", "reversal"]) c[`${name}Target`] = {}
  c.expenseGroupTarget = { value: "" }
  c.categoryHelpTargets = []
  c.cashFieldTargets = []
  c.amountTarget = { value: "12,50" }
  c.descriptionTarget = { value: "IONOS VPS" }
  c.syncExpenseCards = () => {}
  c.typeEditTarget = { focus() {} }
  c.show = c.updateMixedUse = c.updateHints = () => {}
  return c
}
test("first choose a group, then only its expense types are offered", () => {
  const c = setup()
  c.refresh()
  assert.equal(c.categoryChoiceTarget.hidden, true)
  assert.equal(c.categoryTarget.disabled, true)
  assert.equal(c.expenseGroupTarget.required, false)
  c.expenseGroupTarget.value = "Telefon und EDV"
  c.expenseGroupChanged()
  assert.equal(c.categoryChoiceTarget.hidden, true)
  assert.deepEqual(Array.from(c.categoryTarget.options, item => item.value), ["", "expense_it", "expense_phone"])
  c.categoryTarget.value = "expense_it"
  c.refresh()
  assert.equal(c.expenseExampleTarget.textContent, "Zum Beispiel: Hosting.")
  c.expenseGroupTarget.value = "Handel"
  c.expenseGroupChanged()
  assert.equal(c.categoryTarget.value, "")
  assert.equal(c.amountTarget.value, "12,50")
  assert.equal(c.descriptionTarget.value, "IONOS VPS")
})
test("existing categories and cross-group search results select the matching group", () => {
  const c = setup("expense_goods")
  c.refresh()
  assert.equal(c.expenseGroupTarget.value, "Handel")
  c.chooseExpenseCategory({ detail: { key: "expense_it" } })
  assert.equal(c.expenseGroupTarget.value, "Telefon und EDV")
  assert.equal(c.categoryTarget.value, "expense_it")
  assert.equal(c.expenseExampleTarget.textContent, "Zum Beispiel: Hosting.")
  c.chooseExpenseCategory({ detail: { key: "income_small" } })
  assert.equal(c.categoryTarget.value, "expense_it")
})

test("category question follows the selected booking kind", () => {
  const c = setup()
  c.refresh()
  assert.equal(c.categoryLabelTarget.textContent, "Ausgabenart")
  c.kindTargets[0].value = "income"
  c.kindTargets[0].dataset.categoryLabel = "Was hast du erhalten?"
  c.refresh()
  assert.equal(c.categoryLabelTarget.textContent, "Was hast du erhalten?")
})
