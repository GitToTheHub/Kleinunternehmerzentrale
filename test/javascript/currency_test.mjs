import { readFileSync } from "node:fs"
import { runInNewContext } from "node:vm"
import test from "node:test"
import assert from "node:assert/strict"

const priceSource = readFileSync(new URL("../../app/javascript/price_input.js", import.meta.url), "utf8").replaceAll("export function", "function")
const { parsePrice, formatPrice } = runInNewContext(priceSource + "\n({ parsePrice, formatPrice })")

let fetchHandler
function controller(file, name) {
  const source = readFileSync(new URL(`../../app/javascript/controllers/${file}_controller.js`, import.meta.url), "utf8")
  return runInNewContext(source.replace(/^import .*\n/gm, "").replace("export default class", `globalThis.${name} = class`) + `\n${name}`, { parsePrice, formatPrice, Controller: class {}, AbortController, URLSearchParams, Event, fetch: (...args) => fetchHandler(...args) })
}

const Currency = controller("currency", "Currency")
const Lines = controller("invoice_lines", "Lines")

test("Euro does not require conversion details and foreign currency does", () => {
  const currency = new Currency()
  currency.currencyTarget = { value: "EUR" }
  currency.conversionTarget = {}
  currency.conversionInputTargets = [{}, {}, {}]
  let notifications = 0
  currency.dispatch = name => { assert.equal(name, "changed"); notifications++ }
  currency.connect()
  assert.equal(currency.conversionTarget.hidden, true)
  assert.ok(currency.conversionInputTargets.every(input => input.disabled && !input.required))
  currency.currencyTarget.value = "USD"
  currency.changed()
  assert.equal(currency.conversionTarget.hidden, false)
  assert.ok(currency.conversionInputTargets.every(input => !input.disabled && input.required))
  assert.equal(notifications, 2)
})

test("line and invoice sums keep their values when currency changes", () => {
  const currency = { value: "USD" }
  const total = {}
  const quantity = { value: "2" }
  const price = { value: "10.25" }
  const row = {
    closest() { return this },
    querySelector(selector) {
      if (selector.includes("quantity")) return quantity
      if (selector.includes("unit_price")) return price
      return total
    }
  }
  const lines = new Lines()
  lines.element = { closest: () => ({ querySelector: () => currency }) }
  lines.rowTargets = [row]
  lines.totalTarget = {}
  lines.refresh()
  assert.match(total.textContent, /20,50.*USD/)
  assert.equal(lines.totalTarget.textContent, total.textContent)
  currency.value = "EUR"
  lines.refresh()
  assert.match(total.textContent, /20,50.*€/)
  assert.equal(price.value, "10.25")
})


function automatedCurrency() {
  const currency = new Currency()
  currency.currencyTarget = { value: "USD" }
  currency.conversionTarget = {}
  currency.hasRateTarget = true
  currency.hasStatusTarget = true
  currency.statusTarget = {}
  currency.rateTarget = { value: "" }
  currency.rateDateTarget = new EventTarget()
  currency.rateDateTarget.value = ""
  currency.sourceTarget = { value: "" }
  currency.conversionInputTargets = [currency.rateTarget, currency.rateDateTarget, currency.sourceTarget]
  currency.dispatch = () => {}
  currency.urlValue = "/rechnungen/wechselkurs"
  const date = { value: "2026-10-11" }
  currency.element = { querySelector: () => date, dispatchEvent() {} }
  return { currency, date }
}

test("automatic ECB rate fills the rate date and source and refreshes when invoice date changes", async () => {
  const { currency, date } = automatedCurrency()
  const requests = []
  const dates = []
  currency.rateDateTarget.addEventListener("change", () => dates.push(currency.rateDateTarget.value))
  fetchHandler = async url => { requests.push(url); return { ok: true, json: async () => ({ rate: "0.83333333", quote: "1.2", date: "2026-10-09", source: "EZB-Referenzkurs" }) } }
  await currency.load()
  assert.equal(currency.rateTarget.value, "1.2")
  assert.equal(currency.rateDateTarget.value, "2026-10-09")
  assert.equal(currency.sourceTarget.value, "EZB-Referenzkurs")
  date.value = "2026-10-12"
  await currency.load()
  assert.deepEqual(dates, ["", "2026-10-09", "", "2026-10-09"])
  assert.equal(requests.length, 2)
  assert.ok(requests[1].includes("issued_on=2026-10-12"))
})

test("old cached responses are converted to foreign currency per Euro", async () => {
  const { currency } = automatedCurrency()
  fetchHandler = async () => ({ ok: true, json: async () => ({ rate: "0.8", date: "2026-10-09", source: "EZB-Referenzkurs" }) })
  await currency.load()
  assert.equal(currency.rateTarget.value, "1.25")
  assert.match(currency.statusTarget.textContent, /geladen/)
})

test("manual edits abort an in-flight lookup and cannot be overwritten", async () => {
  const { currency } = automatedCurrency()
  let finish
  fetchHandler = () => new Promise(resolve => { finish = resolve })
  const loading = currency.load()
  currency.rateTarget.value = "0.9"
  currency.manualChanged({ target: currency.rateTarget })
  finish({ ok: true, json: async () => ({ rate: "0.8", date: "2026-10-09", source: "EZB-Referenzkurs" }) })
  await loading
  assert.equal(currency.rateTarget.value, "0.9")
  assert.equal(currency.manual, true)
})

test("failed lookups leave empty editable fields instead of a stale rate", async () => {
  const { currency } = automatedCurrency()
  currency.rateTarget.value = "0.8"
  fetchHandler = async () => ({ ok: false, json: async () => ({ error: "Bitte trage den Kurs manuell ein." }) })
  await currency.load()
  assert.equal(currency.rateTarget.value, "")
  assert.match(currency.statusTarget.textContent, /manuell/)
  assert.equal(currency.key, null)
})
