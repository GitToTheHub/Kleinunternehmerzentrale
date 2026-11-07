import { Controller } from "@hotwired/stimulus"
import { parsePrice, formatPrice } from "price_input"

const lineCents = (quantity, price) => {
  const amount = quantity * price
  return Math.round((amount + Number.EPSILON * amount) * 100)
}

export function convertHourlyPrice(quantity, price, toFlat, hourlyRate = price) {
  if (!Number.isFinite(price) || price < 0) throw new Error("Bitte gib zuerst einen gültigen Preis ein.")
  if (toFlat) {
    if (!Number.isFinite(quantity) || quantity < 0.01 || quantity > 999999999.999) throw new Error("Bitte gib zuerst gültige Stunden ein.")
    const total = lineCents(quantity, price) / 100
    if (total > 9999999999.99) throw new Error("Der Gesamtpreis ist zu groß für einen Pauschalpreis.")
    return { quantity: 1, price: total, difference: 0 }
  }
  if (price === 0) return { quantity: 1, price: 0, difference: 0 }
  if (!Number.isFinite(hourlyRate) || hourlyRate <= 0) throw new Error("Bitte trage zuerst einen individuellen oder allgemeinen Stundensatz größer als 0 ein.")
  const hours = Number((price / hourlyRate).toFixed(3))
  if (hours < 0.01 || hours > 999999999.999) throw new Error("Der Pauschalpreis ergibt keine gültige Stundenzahl zwischen 0,01 und 999.999.999,999.")
  return { quantity: hours, price: hourlyRate, difference: (lineCents(hours, hourlyRate) - lineCents(1, price)) / 100 }
}

// Menge ändern und Preise passend zur Einheit vorbelegen.
export default class extends Controller {
  static targets = ["field", "quantity", "unit", "price", "quantityLabel", "priceLabel", "priceHelp", "conversionHint", "hourIcon", "quantityIcon", "packagesIcon", "calendarIcon"]

  connect() {
    this.previousUnit = this.unitTarget.value
    this.updateUnit()
  }

  unitChanged() {
    this.unitTarget.setCustomValidity("")
    this.conversionHintTarget.hidden = true
    const unit = this.unitTarget.value
    const price = parsePrice(this.priceTarget.value)
    try {
      if (this.previousUnit === "HUR" && unit === "LS") {
        const text = this.quantityTarget.value.trim().replace(",", ".")
        const quantity = /^\d+(?:\.\d{1,3})?$/.test(text) && this.quantityTarget.checkValidity() ? Number(text) : NaN
        const converted = convertHourlyPrice(quantity, price, true)
        this.lastHourlyRate = price
        this.setValue(this.priceTarget, converted.price)
        this.setValue(this.quantityTarget, "1")
      } else if (this.previousUnit === "LS" && unit === "HUR") {
        const rate = this.lastHourlyRate > 0 ? this.lastHourlyRate : parsePrice(this.formHourlyRate() || this.rateFromOtherLines())
        const converted = convertHourlyPrice(1, price, false, rate)
        this.setValue(this.priceTarget, converted.price)
        this.setValue(this.quantityTarget, String(converted.quantity).replace(".", ","))
        if (converted.difference !== 0) {
          this.conversionHintTarget.textContent = `Die Stunden sind auf drei Nachkommastellen gerundet. Dadurch ändert sich der Gesamtpreis von ${formatPrice(price)} auf ${formatPrice(price + converted.difference)}.`
          this.conversionHintTarget.hidden = false
        }
      } else if (unit === "HUR" && !(price > 0)) {
        const rate = this.formHourlyRate() || this.rateFromOtherLines()
        if (rate) this.setValue(this.priceTarget, rate)
      }
    } catch (error) {
      this.unitTarget.value = this.previousUnit
      this.conversionHintTarget.textContent = error.message
      this.conversionHintTarget.hidden = false
    }
    this.previousUnit = this.unitTarget.value
    this.updateUnit()
  }

  updateUnit() {
    const flat = this.unitTarget.value === "LS"
    this.hourIconTarget.hidden = this.unitTarget.value !== "HUR"
    this.quantityIconTarget.hidden = ["HUR", "C62", "DAY", "MON"].includes(this.unitTarget.value)
    this.packagesIconTarget.hidden = this.unitTarget.value !== "C62"
    this.calendarIconTarget.hidden = !["DAY", "MON"].includes(this.unitTarget.value)
    this.priceHelpTarget.hidden = !flat
    if (flat) this.priceTarget.setAttribute("aria-describedby", this.priceHelpTarget.id)
    else this.priceTarget.removeAttribute("aria-describedby")
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
