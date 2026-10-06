import { Controller } from "@hotwired/stimulus"

// Menge in ganzen Schritten ändern. Der Stunden-Rechner ("1:30" wird 1,5) erscheint nur,
// wenn die Einheit Stunde gewählt ist und die Menge gerade bearbeitet wird.
export default class extends Controller {
  static targets = ["field", "quantity", "unit", "hours", "time", "result", "price"]

  connect() {
    this.focused = false
    this.toggleHours()
  }

  focus() {
    this.focused = true
    this.toggleHours()
  }

  blur() {
    // Erst nach dem Fokuswechsel prüfen, ob der Fokus noch im Mengenbereich liegt.
    setTimeout(() => {
      this.focused = this.fieldTarget.contains(document.activeElement)
      this.toggleHours()
    })
  }

  // Bei Stunden den Satz einer anderen Stunden-Position derselben Rechnung übernehmen, sonst den gespeicherten
  // Stundensatz, solange noch kein Preis eingetragen ist.
  unitChanged() {
    const price = parseFloat(this.priceTarget.value)
    if (this.unitTarget.value === "HUR" && !(price > 0)) {
      const rate = this.rateFromOtherLines() || this.formHourlyRate()
      if (rate) this.setValue(this.priceTarget, rate)
    }
    this.toggleHours()
  }

  formHourlyRate() {
    return this.element.closest("form")?.dataset.hourlyRate
  }

  // Programmatisch gesetzte Werte melden, damit Summe und Vorschau mitziehen.
  setValue(field, value) {
    field.value = value
    field.dispatchEvent(new Event("change", { bubbles: true }))
  }

  // Beim Wechsel der Kundin oder des Kunden den neuen Stundensatz einsetzen, aber nur bei Stunden-Positionen,
  // die noch keinen Preis oder noch den bisherigen Vorschlag haben.
  rateChanged({ detail: { previous, rate } }) {
    if (this.unitTarget.value !== "HUR") return

    const price = parseFloat(this.priceTarget.value)
    const followsDefault = !(price > 0) || price === parseFloat(previous)
    if (followsDefault) this.setValue(this.priceTarget, rate || "0")
  }

  rateFromOtherLines() {
    const rates = [...document.querySelectorAll("[data-controller~='line-quantity']")]
      .filter((row) => row !== this.element && row.closest("template") === null)
      .map((row) => ({
        unit: row.querySelector("[data-line-quantity-target='unit']")?.value,
        price: row.querySelector("[data-line-quantity-target='price']")?.value
      }))
      .filter((line) => line.unit === "HUR" && parseFloat(line.price) > 0)
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
    this.prefillTime()
  }

  toggleHours() {
    const show = this.unitTarget.value === "HUR"
    if (show && this.hoursTarget.hidden) this.prefillTime()
    this.hoursTarget.hidden = !show
  }

  // Zeigt die bereits eingegebene Menge als Stunden:Minuten an (2,5 wird 2:30).
  prefillTime() {
    const value = parseFloat(this.quantityTarget.value.replace(",", "."))
    if (!(value > 0)) return

    const totalMinutes = Math.round(value * 60)
    const minutes = String(totalMinutes % 60).padStart(2, "0")
    this.timeTarget.value = `${Math.floor(totalMinutes / 60)}:${minutes}`
    this.resultTarget.textContent = ""
  }

  convert() {
    const match = this.timeTarget.value.trim().match(/^(\d+)(?::(\d{1,2}))?$/)
    if (!match || Number(match[2] || 0) > 59) {
      this.resultTarget.textContent = this.timeTarget.value.trim() === "" ? "" : "Bitte als Stunden:Minuten eingeben, zum Beispiel 1:30."
      return
    }

    const hours = Number(match[1]) + Number(match[2] || 0) / 60
    const rounded = Math.round(hours * 100) / 100
    this.setValue(this.quantityTarget, String(rounded))
    this.resultTarget.textContent = `= ${rounded.toLocaleString("de-DE")} Stunden, als Menge übernommen.`
  }
}
