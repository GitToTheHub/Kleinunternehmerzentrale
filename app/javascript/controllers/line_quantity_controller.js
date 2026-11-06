import { Controller } from "@hotwired/stimulus"
import { parsePrice, formatPrice } from "price_input"

// Menge ändern und Preise passend zur Einheit vorbelegen.
export default class extends Controller {
  static targets = ["field", "quantity", "unit", "price", "quantityLabel", "priceLabel", "hourIcon", "quantityIcon", "packagesIcon", "calendarIcon"]

  connect() {
    this.updateUnit()
  }

  // Stundenpositionen übernehmen die gespeicherte Vorgabe, solange noch kein Preis eingetragen ist.
  unitChanged() {
    const price = parsePrice(this.priceTarget.value)
    if (this.unitTarget.value === "HUR" && !(price > 0)) {
      const rate = this.formHourlyRate() || this.rateFromOtherLines()
      if (rate) this.setValue(this.priceTarget, rate)
    }
    this.updateUnit()
  }

  updateUnit() {
    const flat = this.unitTarget.value === "LS"
    this.hourIconTarget.hidden = this.unitTarget.value !== "HUR"
    this.quantityIconTarget.hidden = ["HUR", "C62", "DAY", "MON"].includes(this.unitTarget.value)
    this.packagesIconTarget.hidden = this.unitTarget.value !== "C62"
    this.calendarIconTarget.hidden = !["DAY", "MON"].includes(this.unitTarget.value)
    this.fieldTarget.hidden = flat
    this.quantityTarget.disabled = flat
    this.quantityTarget.required = !flat
    if (flat && this.quantityTarget.value !== "1") this.setValue(this.quantityTarget, "1")
    this.quantityLabelTarget.textContent = ({ HUR: "Stunden", DAY: "Tage", MON: "Monate" })[this.unitTarget.value] || "Menge"
    this.priceLabelTarget.textContent = flat ? "Pauschalpreis" : `Preis pro ${this.unitTarget.selectedOptions[0].textContent}`
  }

  formHourlyRate() {
    const form = this.element.closest("form")
    const currency = form?.querySelector?.("[name='invoice[currency]']")?.value || "EUR"
    if (currency !== "EUR") return null
    return form?.dataset.hourlyRate
  }

  // Programmatisch gesetzte Werte melden, damit Summe und Vorschau mitziehen.
  setValue(field, value) {
    field.value = field === this.priceTarget ? formatPrice(value) : value
    field.dispatchEvent(new Event("change", { bubbles: true }))
  }

  // Beim Wechsel der Kundin oder des Kunden den neuen Stundensatz einsetzen, aber nur bei Stunden-Positionen,
  // die noch keinen Preis oder noch den bisherigen Vorschlag haben.
  rateChanged({ detail: { previous, rate } }) {
    const currency = this.element.closest("form")?.querySelector?.("[name='invoice[currency]']")?.value || "EUR"
    if (this.unitTarget.value !== "HUR" || currency !== "EUR") return

    const price = parsePrice(this.priceTarget.value)
    const followsDefault = !(price > 0) || price === parsePrice(previous)
    if (followsDefault) this.setValue(this.priceTarget, rate || "0")
  }

  rateFromOtherLines() {
    const rates = [...document.querySelectorAll("[data-controller~='line-quantity']")]
      .filter((row) => row !== this.element && row.closest("template") === null)
      .map((row) => ({
        unit: row.querySelector("[data-line-quantity-target='unit']")?.value,
        price: row.querySelector("[data-line-quantity-target='price']")?.value
      }))
      .filter((line) => line.unit === "HUR" && parsePrice(line.price) > 0)
    return rates.length ? rates[rates.length - 1].price : null
  }

  keepFocus(event) {
    event.preventDefault()
    this.quantityTarget.focus()
  }

  increase() {
    this.step(1)
  }

  decrease() {
    this.step(-1)
  }

  step(delta) {
    const current = parseFloat(this.quantityTarget.value.replace(",", ".")) || 0
    const next = Math.max(1, Math.floor(current) + delta)
    this.setValue(this.quantityTarget, String(next))
  }

}
