import { Controller } from "@hotwired/stimulus"
import { calculateExpression } from "controllers/field_calculator_controller"
import { formatPrice } from "price_input"

// Resolve expressions before ordinary price formatting and form change handlers.
export default class extends Controller {
  static values = { price: Boolean }

  connect() {
    this.commit = this.commit.bind(this)
    this.keydown = event => {
      if (event.key === "Enter") {
        event.preventDefault()
        this.commit(event)
        this.element.reportValidity()
      }
    }
    this.edit = event => {
      this.preview()
      if (this.isExpression()) {
        event.stopImmediatePropagation()
        this.element.setCustomValidity("")
      }
    }
    this.element.addEventListener("input", this.edit, true)
    this.element.addEventListener("change", this.commit, true)
    this.element.addEventListener("blur", this.commit, true)
    this.element.addEventListener("keydown", this.keydown)
  }

  disconnect() {
    this.element.removeEventListener("input", this.edit, true)
    this.element.removeEventListener("change", this.commit, true)
    this.element.removeEventListener("blur", this.commit, true)
    this.element.removeEventListener("keydown", this.keydown)
  }

  isExpression() {
    return /[+*/()×÷−:]|\d\s*-|[a-z€]/i.test(this.element.value)
  }

  result() {
    const result = calculateExpression(this.element.value, { withUnit: true, price: this.priceValue })
    if (this.priceValue && result.unit === "time") throw new Error("Bitte multipliziere die Zeit mit einem Stundensatz, z. B. (30 min + 1 Std) * 60.")
    const precision = this.priceValue ? 2 : 3
    const value = Number(result.value.toFixed(precision))
    const minimum = this.priceValue ? 0 : 0.01
    const maximum = this.priceValue ? 9999999999.99 : 999999999.999
    if (value < minimum || value > maximum) throw new Error("Das Ergebnis liegt außerhalb des erlaubten Bereichs für dieses Feld.")
    return value
  }

  preview() {
    const output = document.getElementById(`${this.element.id}_calculation_result`)
    if (!output) return
    output.hidden = true
    output.textContent = ""
    if (!this.isExpression()) return
    try {
      const value = this.result()
      output.textContent = `Ergebnis: ${value.toLocaleString("de-DE", { minimumFractionDigits: this.priceValue ? 2 : 0, maximumFractionDigits: this.priceValue ? 2 : 3 })}`
      output.hidden = false
    } catch (_) {
      // Incomplete expressions are normal while typing; validate on commit.
    }
  }

  commit(event) {
    if (!this.isExpression()) {
      if (!this.priceValue) {
        const raw = this.element.value.trim().replace(",", ".")
        const valid = raw === "" || (/^\d+(?:\.\d{1,3})?$/.test(raw) && Number(raw) >= 0.01 && Number(raw) <= 999999999.999)
        this.element.setCustomValidity(valid ? "" : "Bitte eine gültige Menge ab 0,01 mit höchstens drei Nachkommastellen eingeben.")
        if (valid && raw !== this.element.value) {
          this.element.value = raw
          this.element.dispatchEvent(new Event("input", { bubbles: true }))
        }
      }
      return
    }
    try {
      const value = this.result()
      this.element.value = this.priceValue ? formatPrice(value) : String(value)
      this.element.setCustomValidity("")
      this.element.dispatchEvent(new Event("input", { bubbles: true }))
      this.element.dispatchEvent(new Event("change", { bubbles: true }))
    } catch (error) {
      event?.stopImmediatePropagation()
      this.element.setCustomValidity(error.message)
      this.element.reportValidity()
    }
  }
}
