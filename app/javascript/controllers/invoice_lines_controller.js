import { Controller } from "@hotwired/stimulus"
import { parsePrice, formatPrice } from "price_input"

export default class extends Controller {
  static targets = ["list", "template", "row", "title", "remove", "total"]

  initialize() {
    this.index = 0
  }

  connect() {
    this.index = this.rowTargets.length
    this.renumber()
    this.rowTargets.forEach((row) => this.updateSummary({ currentTarget: row }))
  }

  currency() {
    return this.element.closest("form")?.querySelector?.("[name='invoice[currency]']")?.value || "EUR"
  }

  refresh() {
    this.rowTargets.forEach(row => this.updateSummary({ currentTarget: row }))
  }

  field(row, name) {
    return row.querySelector(`[name$='[${name}]']`)
  }

  updateSummary(event) {
    const row = (event.currentTarget || event.target).closest("[data-invoice-lines-target='row']")
    const amount = this.lineCents(row) / 100
    row.querySelector("[data-summary='total']").textContent = amount.toLocaleString("de-DE", { style: "currency", currency: this.currency(), currencyDisplay: this.currency() === "EUR" ? "symbol" : "code" })
    this.updateTotal()
  }

  // Round each position to cents before adding, as InvoiceLine#line_total does.
  lineCents(row) {
    const quantity = parseFloat(this.field(row, "quantity").value.replace(",", ".")) || 0
    const price = parsePrice(this.field(row, "unit_price").value) || 0
    const amount = quantity * price
    return Math.round((amount + Number.EPSILON * amount) * 100)
  }

  updateTotal() {
    const money = (n) => n.toLocaleString("de-DE", { style: "currency", currency: this.currency(), currencyDisplay: this.currency() === "EUR" ? "symbol" : "code" })
    const cents = this.rowTargets.reduce((sum, row) => sum + this.lineCents(row), 0)
    this.totalTarget.textContent = money(cents / 100)
  }

  add() {
    const index = this.index++
    const previous = this.rowTargets[this.rowTargets.length - 1]
    this.listTarget.insertAdjacentHTML("beforeend", this.templateTarget.innerHTML.replaceAll("NEW_RECORD", index))
    const row = this.listTarget.lastElementChild
    this.copyUnit(previous, row)
    this.renumber()
    this.updateSummary({ currentTarget: row })
    this.field(row, "description").focus({ preventScroll: true })
    this.element.dispatchEvent(new Event("input", { bubbles: true }))
  }

  // Neue Position übernimmt die Einheit der vorherigen; bei Stunden folgt der Stundensatz, die Menge nie.
  copyUnit(previous, row) {
    if (!previous) return

    const unit = row.querySelector("select[name$='[unit_code]']")
    const previousUnit = this.field(previous, "unit_code")
    if (!Array.from(unit.options).some(option => option.value === previousUnit.value)) {
      return
    }
    unit.value = previousUnit.value
    if (unit.value !== "HUR") return

    // Der Controller der neuen Zeile ist noch nicht verbunden, daher wird der Preis hier direkt gesetzt.
    const rate = this.rowTargets.filter((r) => r !== row && this.field(r, "unit_code").value === "HUR")
      .map((r) => this.field(r, "unit_price").value).filter((v) => parsePrice(v) > 0).pop()
    this.field(row, "unit_price").value = formatPrice((this.currency() === "EUR" ? this.element.closest("form").dataset.hourlyRate : 0) || rate || 0)
  }

  remove(event) {
    event.preventDefault()
    event.stopPropagation()
    const row = event.currentTarget.closest("[data-invoice-lines-target='row']")
    if (this.rowTargets.length <= 1) return this.reset(row)

    row.remove()
    this.renumber()
    this.updateTotal()
    this.element.dispatchEvent(new Event("input", { bubbles: true }))
  }

  // Die einzige Position kann nicht gelöscht werden und wird stattdessen auf den Ausgangszustand gesetzt.
  reset(row) {
    const values = { description: "", details: "", quantity: "1", unit_code: "C62", unit_price: "0,00" }
    Object.entries(values).forEach(([name, value]) => { this.field(row, name).value = value })
    this.field(row, "unit_price").dispatchEvent(new Event("change", { bubbles: true }))
    row.querySelector("[data-controller~='rich-text']")?.dispatchEvent(new CustomEvent("rich-text:clear"))
    this.field(row, "unit_code").dispatchEvent(new Event("change", { bubbles: true }))
    this.field(row, "description").focus({ preventScroll: true })
  }

  // Zeigt "Position 2 von 3" über jeder Leistung.
  renumber() {
    const rows = this.listTarget.querySelectorAll("[data-invoice-lines-target='row']")
    this.removeTargets.forEach((button) => {
      const label = rows.length <= 1 ? "Position leeren" : "Position löschen"
      button.title = label
      button.setAttribute("aria-label", label)
    })
    rows.forEach((row, i) => {
      row.querySelector("[data-invoice-lines-target='title']").textContent = `Position ${i + 1} von ${rows.length}`
    })
  }
}
