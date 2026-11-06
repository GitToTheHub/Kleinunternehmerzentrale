import { readFileSync } from "node:fs"
import { runInNewContext } from "node:vm"
import test from "node:test"
import assert from "node:assert/strict"

const source = readFileSync(new URL("../../app/javascript/controllers/iban_field_controller.js", import.meta.url), "utf8")
const IbanField = runInNewContext(source.replace(/^import .*\n/, "").replace("export default class", "globalThis.IbanField = class") + "\nIbanField", { Controller: class {} })

test("a short IBAN immediately shows its required length and blocks submission", () => {
  const controller = setup("DE 12345678")
  assert.match(controller.statusTarget.textContent, /Zu kurz.*22 Zeichen/)
  assert.equal(controller.inputTarget.invalid, "true")
  assert.notEqual(controller.inputTarget.validationMessage, "")
})

test("a wrong checksum can be corrected or the optional IBAN cleared", () => {
  const controller = setup("DE89370400440532013001")
  assert.match(controller.inputTarget.validationMessage, /Prüfsumme/)
  controller.inputTarget.value = "de89 3704 0044 0532 0130 00"
  controller.check()
  assert.equal(controller.inputTarget.validationMessage, "")
  assert.equal(controller.statusTarget.dataset.state, "ok")
  controller.inputTarget.value = ""
  controller.check()
  assert.equal(controller.inputTarget.validationMessage, "")
  assert.equal(controller.statusTarget.textContent, "")
  assert.equal(controller.inputTarget.invalid, "false")
})

function setup(value) {
  const controller = new IbanField()
  controller.lengthsValue = { DE: 22 }
  controller.statusTarget = { dataset: {} }
  controller.inputTarget = {
    value,
    setCustomValidity(message) { this.validationMessage = message },
    setAttribute(_name, value) { this.invalid = value },
  }
  controller.connect()
  return controller
}
