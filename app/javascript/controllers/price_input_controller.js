import { Controller } from "@hotwired/stimulus"
import { parsePrice, formatPrice } from "price_input"

export default class extends Controller {
  connect() { this.format() }

  validate() {
    const value = this.element.value
    const price = parsePrice(value)
    this.element.setCustomValidity(value === "" || (Number.isFinite(price) && price <= 9999999999.99) ? "" : "Bitte einen gültigen Preis mit höchstens zwei Nachkommastellen eingeben.")
  }

  format() {
    this.element.value = formatPrice(this.element.value)
    this.validate()
  }
}
