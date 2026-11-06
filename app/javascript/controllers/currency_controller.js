import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["currency", "conversion", "conversionInput", "rate", "rateDate", "source", "status", "unit"]
  static values = { url: String }

  connect() {
    this.manual = this.hasRateTarget && !!this.rateTarget.value
    this.changed()
  }

  disconnect() { this.request?.abort() }

  changed() {
    const currency = this.currencyTarget.value
    const foreign = currency !== "EUR"
    if (this.hasUnitTarget) this.unitTarget.textContent = currency
    if (this.previousCurrency && this.previousCurrency !== currency) {
      this.request?.abort()
      this.key = null
      this.manual = false
      this.clearConversion()
    }
    this.previousCurrency = currency
    this.conversionTarget.hidden = !foreign
    this.conversionInputTargets.forEach(input => {
      input.disabled = !foreign
      input.required = foreign
    })
    this.dispatch("changed")
    if (foreign && this.hasRateTarget) {
      if (this.manual) this.showStatus("Gespeicherter oder manuell eingegebener Kurs. Du kannst ihn ändern oder neu laden.")
      else this.load()
    }
  }

  clearConversion() {
    this.conversionInputTargets.forEach(input => { input.value = "" })
    if (this.hasRateTarget) this.rateDateTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  dateChanged(event) {
    if (event.target.id !== "invoice_issued_on" || this.currencyTarget.value === "EUR") return
    if (this.manual) this.showStatus("Rechnungsdatum geändert: Bitte prüfe deinen manuellen Kurs oder lade den EZB-Kurs neu.")
    else this.load()
  }

  manualChanged(event) {
    this.manual = true
    this.request?.abort()
    if (event.target === this.rateTarget && this.sourceTarget.value === "EZB-Referenzkurs") this.sourceTarget.value = "Manuell angepasster Kurs"
    this.showStatus("Manuelle Kursangaben werden mit der Rechnung gespeichert.")
  }

  reload() {
    this.manual = false
    this.key = null
    return this.load()
  }

  showStatus(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }

  async load() {
    const currency = this.currencyTarget.value
    if (currency === "EUR") return
    const date = this.element.querySelector("#invoice_issued_on").value
    const key = `${currency}/${date}`
    if (key === this.key) return
    this.key = key
    this.request?.abort()
    const request = this.request = new AbortController()
    this.clearConversion()
    this.showStatus("EZB-Kurs wird geladen …")
    try {
      const query = new URLSearchParams({ currency, issued_on: date })
      const response = await fetch(`${this.urlValue}?${query}`, { headers: { Accept: "application/json" }, signal: request.signal })
      const result = await response.json()
      if (request.signal.aborted) return
      if (!response.ok) throw new Error(result.error || "Kurs konnte nicht geladen werden. Bitte trage ihn manuell ein.")
      const quote = Number(result.quote ?? (1 / Number(result.rate)))
      if (!Number.isFinite(quote) || quote <= 0) throw new Error("Kurs konnte nicht geladen werden. Bitte trage ihn manuell ein.")
      this.rateTarget.value = String(Number(quote.toFixed(8)))
      this.rateDateTarget.value = result.date
      this.rateDateTarget.dispatchEvent(new Event("change", { bubbles: true }))
      this.sourceTarget.value = result.source
      this.showStatus(`EZB-Kurs vom ${result.date.split("-").reverse().join(".")} geladen. Du kannst ihn bei Bedarf ändern.`)
      this.element.dispatchEvent(new Event("input", { bubbles: true }))
    } catch (error) {
      if (!request.signal.aborted) {
        this.key = null
        this.showStatus(error.message || "Kurs konnte nicht geladen werden. Bitte trage ihn manuell ein.")
      }
    }
  }
}
