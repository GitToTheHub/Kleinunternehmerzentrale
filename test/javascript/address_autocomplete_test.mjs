import { readFileSync } from "node:fs"
import { runInNewContext } from "node:vm"
import test from "node:test"
import assert from "node:assert/strict"

const source = readFileSync(new URL("../../app/javascript/controllers/address_autocomplete_controller.js", import.meta.url), "utf8")
let timer, delay, respond
const fields = {}
const Autocomplete = runInNewContext(source.replace(/^import .*\n/, "").replace("export default class", "globalThis.Autocomplete = class") + "\nAutocomplete", {
  Controller: class {}, AbortController, URLSearchParams, Event,
  document: { getElementById: id => fields[id], createElement: () => ({ setAttribute() {}, addEventListener() {} }) },
  clearTimeout() { timer = null },
  setTimeout(callback, timeout) { timer = callback; delay = timeout; return 1 },
  fetch: (...args) => respond(...args),
})

function setup() {
  const controller = new Autocomplete()
  controller.streetTarget = { value: "Beispielstraße 6", setAttribute(name, value) { this[name] = value } }
  controller.listTarget = { hidden: false, children: [], replaceChildren() { this.children = [] }, appendChild(item) { this.children.push(item) } }
  controller.statusTarget = { hidden: false }
  controller.connect()
  return controller
}

test("selecting a saved customer's street cancels suggestions without searching", () => {
  const controller = setup()
  controller.search({ isTrusted: true })
  assert.equal(delay, 350)
  const request = controller.abort = new AbortController()
  controller.search({ isTrusted: false })
  assert.equal(timer, null)
  assert.equal(request.signal.aborted, true)
  assert.equal(controller.listTarget.hidden, true)
  assert.equal(controller.statusTarget.hidden, true)
  assert.equal(controller.streetTarget["aria-expanded"], "false")
  controller.search({ isTrusted: true })
  assert.equal(typeof timer, "function")
})

test("an older search cannot reopen suggestions after the customer changes", async () => {
  const controller = setup()
  let finish
  let started
  const ready = new Promise(resolve => { started = resolve })
  respond = async () => ({ ok: true, json: () => new Promise(resolve => { finish = resolve; started() }) })
  let rendered = false
  controller.render = () => { rendered = true }
  const searching = controller.fetchResults("Beispielstraße")
  await ready
  controller.search({ isTrusted: false })
  finish({ features: [{ properties: { street: "Alte Straße" } }] })
  await searching
  assert.equal(rendered, false)
  assert.equal(controller.listTarget.hidden, true)
})

test("suggestions include streets by name and addresses with house numbers", async () => {
  const controller = setup()
  let requestedUrl
  respond = async url => {
    requestedUrl = url
    return { ok: true, json: async () => ({ features: [
      { properties: { street: "Beispielstraße", housenumber: "6a", postcode: "27568", city: "Bremerhaven" } },
      { properties: { street: "Beispielstraße" } },
      { properties: { name: "Barkhausenstraße", osm_key: "highway", postcode: "27568", city: "Bremerhaven" } },
      { properties: { name: "Laden", housenumber: "6" } },
    ] }) }
  }
  let results
  controller.render = () => { results = controller.results }
  await controller.fetchResults("Beispielstraße")
  assert.deepEqual(new URL(requestedUrl, "https://example.test").searchParams.getAll("layer"), ["house", "street"])
  assert.equal(results.length, 3)
  assert.equal(results[0].street, "Beispielstraße 6a")
  assert.equal(results[0].postalCode, "27568")
  assert.equal(results[2].street, "Barkhausenstraße")
  assert.equal(results[2].city, "Bremerhaven")
  assert.equal(controller.statusTarget.hidden, true)
})

test("no matches show a manual entry hint without changing the street", async () => {
  const controller = setup()
  respond = async () => ({ ok: true, json: async () => ({ features: [] }) })
  await controller.fetchResults("Beispielstraße 6")
  assert.equal(controller.listTarget.hidden, true)
  assert.equal(controller.statusTarget.hidden, false)
  assert.match(controller.statusTarget.textContent, /Straße und Hausnummer selbst ein/)
  assert.equal(controller.streetTarget.value, "Beispielstraße 6")
  controller.search({ isTrusted: true })
  assert.equal(controller.statusTarget.hidden, true)
})

test("choosing a street immediately finds house numbers in the chosen town", async () => {
  const controller = setup()
  controller.prefixValue = "buyer"
  controller.streetTarget.focus = function() { this.focused = true }
  controller.streetTarget.setSelectionRange = function(start, end) { this.selection = [start, end] }
  controller.streetTarget.dispatchEvent = () => {}
  fields.invoice_buyer_street = controller.streetTarget
  fields.invoice_buyer_postal_code = { dispatchEvent() {} }
  fields.invoice_buyer_city = { dispatchEvent() {} }
  controller.results = [controller.toAddress({ name: "Barkhausenstraße", osm_key: "highway", postcode: "27568", city: "Bremerhaven" })]
  let requestedUrl
  respond = async url => {
    requestedUrl = url
    return { ok: true, json: async () => ({ features: [
      { properties: { street: "Barkhausenstraße", housenumber: "6", postcode: "27568", city: "Bremerhaven" } },
      { properties: { street: "Barkhausenstraße", housenumber: "8", postcode: "99086", city: "Erfurt" } },
      { properties: { street: "Andere Straße", housenumber: "6", postcode: "27568", city: "Bremerhaven" } },
      { properties: { street: "Barkhausenstraße", postcode: "27568", city: "Bremerhaven" } },
    ] }) }
  }
  await controller.choose(0)
  assert.equal(controller.streetTarget.value, "Barkhausenstraße ")
  assert.equal(fields.invoice_buyer_postal_code.value, "27568")
  assert.equal(fields.invoice_buyer_city.value, "Bremerhaven")
  assert.equal(controller.streetTarget.focused, true)
  assert.deepEqual(controller.streetTarget.selection, [17, 17])
  const params = new URL(requestedUrl, "https://example.test").searchParams
  assert.equal(params.get("q"), "Barkhausenstraße, 27568, Bremerhaven")
  assert.deepEqual(params.getAll("layer"), ["house"])
  assert.equal(controller.results.length, 1)
  assert.equal(controller.results[0].street, "Barkhausenstraße 6")
  assert.equal(controller.listTarget.hidden, false)
  assert.equal(controller.streetTarget["aria-expanded"], "true")
  await controller.choose(0)
  assert.equal(controller.streetTarget.value, "Barkhausenstraße 6")
  assert.equal(controller.listTarget.hidden, true)
})

test("typing a house number keeps the selected town while changing the street resets it", async () => {
  const controller = setup()
  controller.selectedStreet = controller.toAddress({ street: "Barkhausenstraße", postcode: "27568", city: "Bremerhaven" })
  const urls = []
  respond = async url => { urls.push(url); return { ok: true, json: async () => ({ features: [] }) } }
  controller.streetTarget.value = "Barkhausenstraße 6"
  controller.search({ isTrusted: true })
  await timer()
  assert.equal(new URL(urls[0], "https://example.test").searchParams.get("q"), "Barkhausenstraße 6, 27568, Bremerhaven")
  assert.match(controller.statusTarget.textContent, /Hausnummer selbst/)
  assert.equal(controller.streetTarget.value, "Barkhausenstraße 6")
  controller.streetTarget.value = "Hauptstraße"
  controller.search({ isTrusted: true })
  await timer()
  assert.equal(new URL(urls[1], "https://example.test").searchParams.get("q"), "Hauptstraße")
  assert.equal(controller.selectedStreet, null)
})
