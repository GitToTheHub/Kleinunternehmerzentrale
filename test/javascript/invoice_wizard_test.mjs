import { readFileSync } from "node:fs"
import { runInNewContext } from "node:vm"
import test from "node:test"
import assert from "node:assert/strict"

const priceSource = readFileSync(new URL("../../app/javascript/price_input.js", import.meta.url), "utf8").replaceAll("export function", "function")
const { parsePrice, formatPrice } = runInNewContext(priceSource + "\n({ parsePrice, formatPrice })")

const source = readFileSync(new URL("../../app/javascript/controllers/invoice_wizard_controller.js", import.meta.url), "utf8")
const Wizard = runInNewContext(source.replace(/^import .*\n/gm, "").replace("export default class", "globalThis.Wizard = class") + "\nWizard", {
  parsePrice, formatPrice, Controller: class {},
})

function setup(errorStep = -1, savedProfile = false, sellerFields = []) {
  const wizard = new Wizard()
  wizard.savedProfileValue = savedProfile
  wizard.element = { noValidate: false, querySelectorAll: () => [] }
  wizard.stepTargets = Array.from({ length: 4 }, (_, index) => ({
    fields: [],
    scrolls: [],
    querySelector: (selector) => selector === ".field_with_errors" ? index === errorStep : { focus() {} },
    querySelectorAll() { return this.fields },
    scrollIntoView(options) { this.scrolls.push(options) },
  }))
  wizard.stepTargets[0].fields = sellerFields
  wizard.connect()
  return wizard
}

function invalidField(parentElement) {
  return { willValidate: true, validity: { valid: false }, parentElement, reports: 0,
    reportValidity() { this.reports++ },
    scrollIntoView() {} }
}

test("saved complete seller details start with the customer and remain editable", () => {
  const wizard = setup(-1, true, [{ willValidate: true, validity: { valid: true } }])
  assert.equal(wizard.current, 1)
  wizard.show(0)
  assert.equal(wizard.current, 0)
})

test("incomplete saved details and server errors keep the seller step visible", () => {
  assert.equal(setup(-1, true, [invalidField(null)]).current, 0)
  assert.equal(setup(0, true).current, 0)
  assert.equal(setup().current, 0)
})

test("focusing a section leaves all sections visible and preserves entered values", () => {
  const wizard = setup()
  const field = invalidField(wizard.element)
  field.value = "Eingegebener Firmenname"
  wizard.stepTargets[0].fields.push(field)
  wizard.activate({ target: { closest: () => wizard.stepTargets[3] } })
  assert.equal(wizard.current, 3)
  assert.equal(wizard.stepTargets.some((step) => step.hidden), false)
  assert.equal(wizard.stepTargets[3].scrolls.length, 0)
  wizard.show(0)
  assert.equal(field.value, "Eingegebener Firmenname")
})

test("submission reveals the first invalid step and opens collapsed positions", () => {
  const wizard = setup()
  wizard.show(3)
  const details = { tagName: "DETAILS", open: false, parentElement: wizard.element }
  wizard.stepTargets[0].fields.push(invalidField(details))
  let prevented = false
  wizard.submit({ preventDefault() { prevented = true } })
  assert.equal(prevented, true)
  assert.equal(wizard.current, 0)
  assert.equal(details.open, true)
})

test("a valid invoice can be submitted from any open section", () => {
  const wizard = setup()
  let prevented = false
  wizard.submit({ preventDefault() { prevented = true } })
  assert.equal(prevented, false)
})

test("customer fields are protected when editing seller details and editable on customer focus", () => {
  const wizard = setup()
  const customer = { value: "Kundin GmbH", readOnly: false }
  wizard.stepTargets[1].fields.push(customer)
  wizard.show(0)
  assert.equal(customer.readOnly, true)
  wizard.activate({ target: { closest: () => wizard.stepTargets[1] } })
  assert.equal(customer.readOnly, false)
  wizard.show(3)
  assert.equal(customer.readOnly, true)
  assert.equal(customer.value, "Kundin GmbH")
  wizard.disconnect()
  assert.equal(customer.readOnly, false)
})

test("protected customer fields still validate on submission", () => {
  const wizard = setup()
  const customer = invalidField(wizard.element)
  Object.defineProperty(customer, "willValidate", { get() { return !this.readOnly } })
  wizard.stepTargets[1].fields.push(customer)
  wizard.show(3)
  assert.equal(customer.readOnly, true)
  let prevented = false
  wizard.submit({ preventDefault() { prevented = true } })
  assert.equal(prevented, true)
  assert.equal(wizard.current, 1)
  assert.equal(customer.readOnly, false)
  assert.equal(customer.reports, 1)
})

test("server validation errors reopen their step and native validation is restored on disconnect", () => {
  const wizard = setup(2)
  assert.equal(wizard.current, 2)
  assert.equal(wizard.stepTargets.some((step) => step.hidden), false)
  assert.equal(wizard.element.noValidate, true)
  wizard.disconnect()
  assert.equal(wizard.element.noValidate, false)
})
