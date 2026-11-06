import { Controller } from "@hotwired/stimulus"
import { parsePrice } from "price_input"

export default class extends Controller {
  static targets = ["step"]
  static values = { savedProfile: Boolean }

  connect() {
    this.originalNoValidate = this.element.noValidate
    // Validate after revealing the relevant step so the browser can focus its field.
    this.element.noValidate = true
    const errorStep = this.stepTargets.findIndex((step) => step.querySelector(".field_with_errors"))
    const initialStep = this.savedProfileValue && !this.invalidField(0) ? 1 : 0
    this.show(errorStep >= 0 ? errorStep : initialStep, false)
  }

  disconnect() {
    this.element.noValidate = this.originalNoValidate
    this.protectCustomerFields(false)
  }

  show(index, focus = true) {
    this.current = index
    this.protectCustomerFields(index !== 1)
    if (focus) {
      const step = this.stepTargets[index]
      step.querySelector("h2").focus({ preventScroll: true })
      step.scrollIntoView({ behavior: "smooth", block: "start" })
    }
  }

  protectCustomerFields(readOnly) {
    // Read-only fields are still submitted, but are excluded from browser autofill.
    this.stepTargets[1].querySelectorAll('input[name^="invoice[buyer_"]').forEach((field) => {
      field.readOnly = readOnly
    })
  }

  activate(event) {
    const step = event.target.closest("[data-invoice-wizard-target='step']")
    const index = this.stepTargets.indexOf(step)
    if (index >= 0) this.show(index, false)
  }

  invalidField(index) {
    return Array.from(this.stepTargets[index].querySelectorAll("input, select, textarea"))
      .find((field) => {
        const readOnly = field.readOnly
        field.readOnly = false
        const invalid = field.willValidate && !field.validity.valid
        field.readOnly = readOnly
        return invalid
      })
  }

  validate(index) {
    const invalid = this.invalidField(index)
    if (!invalid) return true

    this.show(index, false)
    // Invoice positions and optional sections can contain collapsed fields.
    for (let parent = invalid.parentElement; parent && parent !== this.element; parent = parent.parentElement) {
      if (parent.tagName === "DETAILS") parent.open = true
      if (parent.tagName === "DIALOG" && !parent.open) parent.showModal()
    }
    // Centering keeps the field clear of the sticky footer, so the browser's focus scroll has nothing left to do.
    invalid.scrollIntoView({ block: "center", behavior: "instant" })
    invalid.reportValidity()
    return false
  }

  submit(event) {
    if (event.defaultPrevented) return
    for (let index = 0; index < this.stepTargets.length; index++) {
      if (!this.validate(index)) {
        event.preventDefault()
        return
      }
    }
    if (event.submitter?.dataset.invoicePreview === "true") return

    const freePositions = Array.from(this.element.querySelectorAll("[data-invoice-lines-target='row']"))
      .flatMap((row, index) => parsePrice(row.querySelector("[name$='[unit_price]']").value) === 0 ? [index + 1] : [])
    if (freePositions.length && !window.confirm(`Preis von 0 € in Position ${freePositions.join(", ")}. Soll die Rechnung trotzdem fortgesetzt werden?`)) {
      event.preventDefault()
    }
  }
}
