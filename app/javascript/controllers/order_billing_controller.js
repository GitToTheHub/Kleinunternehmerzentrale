import { Controller } from "@hotwired/stimulus"
import { parsePrice, formatPrice } from "price_input"

export default class extends Controller {
  static targets = ["panel", "enabled", "calculation", "mode", "percentField", "amountField", "percent", "amount", "total", "requested", "requestedLabel", "remaining", "priorRow", "prior", "positionsHeading", "scopeTotalLabel", "scopeHint", "basis", "totalFields"]
  static values = { linked: Boolean, total: Number, prior: Number }

  connect() {
    this.positionValues = JSON.parse(this.panelTarget.dataset.initialValues || "{}")
    this.positionRows = new Map()
    this.update()
  }

  update() {
    const kind = this.element.querySelector('[name="invoice[billing_kind]"]:checked')?.value
    const partial = ["advance", "progress"].includes(kind)
    const direct = this.basisTargets.some(input => input.checked && input.value === "direct")
    const active = partial && !direct && this.enabledTarget.value === "1"
    this.scopeHintTarget.hidden = partial && !direct && !this.linkedValue
    if (this.linkedValue) {
      this.scopeHintTarget.textContent = "Die Positionen beschreiben den vereinbarten Gesamtumfang des Auftrags mit seinen Preisen."
    } else if (partial && direct) {
      this.scopeHintTarget.textContent = "Beschreibe nur die Lieferung oder Leistung, für die du jetzt eine Zahlung verlangst, und trage den angeforderten Betrag ein. Den vollständigen Auftrag erfasst du später in der Schlussrechnung."
    } else if (kind === "final") {
      this.scopeHintTarget.textContent = "Erfasse den vollständigen Auftrag mit allen Positionen zum Gesamtpreis. Die ausgewählten erhaltenen Anzahlungen und Abschläge werden abgezogen."
    } else if (partial) {
      this.scopeHintTarget.textContent = ""
    } else {
      this.scopeHintTarget.textContent = "Beschreibe jede Leistung oder jeden Artikel als eigene Position mit Menge und Preis."
    }
    this.panelTarget.hidden = !partial
    this.calculationTarget.hidden = !active
    const individual = active && this.basisTargets.some(input => input.checked && input.value === "positions")
    this.basisTargets.forEach(input => { input.disabled = !partial || (!this.linkedValue && !!this.element.querySelector('[name="invoice[billing_root_id]"]') && input.value !== "direct") })
    this.totalFieldsTarget.hidden = individual
    this.modeTarget.disabled = !active || individual
    this.percentFieldTarget.hidden = this.modeTarget.value !== "percent"
    this.amountFieldTarget.hidden = this.modeTarget.value !== "amount"
    this.percentTarget.disabled = !active || individual || this.modeTarget.value !== "percent"
    this.amountTarget.disabled = !active || individual || this.modeTarget.value !== "amount"
    this.percentTarget.required = !this.percentTarget.disabled
    this.amountTarget.required = !this.amountTarget.disabled
    this.positionsHeadingTarget.textContent = active ? "Positionen des Gesamtauftrags" : partial && direct ? "Positionen der angeforderten Zahlung" : "Rechnungspositionen"
    if (this.hasScopeTotalLabelTarget) this.scopeTotalLabelTarget.textContent = active || kind === "final" ? "Gesamtpreis des Auftrags:" : partial && direct ? "Jetzt angeforderter Betrag:" : "Gesamtsumme:"
    const positions = this.positions()
    this.syncPositionFields(positions, individual)
    if (!active) return
    const total = this.linkedValue ? this.totalValue : this.roundMoney(positions.reduce((sum, line) => sum + line.total, 0))
    const requested = individual ? positions.reduce((sum, line) => {
      const row = this.positionRows.get(line.key)
      const value = parsePrice(row.value.value)
      const amount = row.mode.value === "percent" ? this.roundMoney(line.total * value / 100) : value
      row.output.textContent = `${kind === "advance" ? "Diese Anzahlung" : "Dieser Abschlag"}: ${this.money(amount)}`
      row.value.setCustomValidity(!Number.isFinite(value) || value < 0 || (row.mode.value === "percent" && value > 100) || amount > line.remaining ? "Der Anteil darf den noch nicht abgerechneten Positionsbetrag nicht überschreiten." : "")
      return sum + amount
    }, 0) : this.modeTarget.value === "percent" ? this.roundMoney(total * parsePrice(this.percentTarget.value) / 100) : parsePrice(this.amountTarget.value)
    const money = value => this.money(value)
    this.totalTarget.textContent = money(total)
    this.requestedTarget.textContent = money(requested)
    this.requestedLabelTarget.textContent = kind === "advance" ? "Diese Anzahlung" : "Dieser Abschlag"
    this.remainingTarget.textContent = money(this.roundMoney(total - this.priorValue - requested))
    this.priorRowTarget.hidden = this.priorValue === 0
    this.priorTarget.textContent = money(this.priorValue)
  }
  chooseBasis(event) {
    this.enabledTarget.value = event.currentTarget.value === "direct" ? "0" : "1"
    this.update()
    this.element.dispatchEvent(new Event("input", { bubbles: true }))
  }

  roundMoney(value) {
    return Math.round((value + Number.EPSILON * value) * 100) / 100
  }

  money(value) {
    return Number.isFinite(value) ? value.toLocaleString("de-DE", { style: "currency", currency: "EUR" }) : "—"
  }

  positions() {
    if (this.linkedValue) return [...this.element.querySelectorAll("[data-order-position-key]")].map(row => ({ element: row, key: row.dataset.orderPositionKey, title: row.dataset.orderPositionTitle, total: Number(row.dataset.orderPositionTotal), remaining: Number(row.dataset.orderPositionRemaining) }))
    return [...this.element.querySelectorAll('[data-invoice-lines-target="row"]')].map((row, index) => {
      const field = name => row.querySelector(`[name$='[${name}]']`)
      const key = field("description").name.match(/\[invoice_lines_attributes\]\[([^\]]+)\]/)[1]
      const quantity = field("unit_code").value === "LS" ? 1 : Number(field("quantity").value.replace(",", "."))
      const total = this.roundMoney(quantity * parsePrice(field("unit_price").value))
      return { element: row.querySelector(".invoice-line__pricing"), key, title: field("description").value || `Position ${index + 1}`, total, remaining: total }
    })
  }

  syncPositionFields(positions, enabled) {
    const keys = new Set(positions.map(line => line.key))
    for (const [key, row] of this.positionRows) {
      if (!keys.has(key)) { row.element.remove(); this.positionRows.delete(key) }
    }
    // Fields exist only after the user selects position-specific calculation.
    if (!enabled) {
      for (const row of this.positionRows.values()) { row.element.hidden = true; row.mode.disabled = true; row.value.disabled = true }
      return
    }
    positions.forEach((line, index) => {
      let row = this.positionRows.get(line.key)
      if (!row) {
        const element = document.createElement("div")
        element.className = "position-allocation"
        const heading = document.createElement("strong")
        const info = document.createElement("small")
        const fields = document.createElement("div")
        fields.className = "form-grid"
        const field = (labelText, input) => {
          const wrapper = document.createElement("div")
          wrapper.className = "field"
          const label = document.createElement("label")
          label.htmlFor = input.id
          label.textContent = labelText
          wrapper.append(label, input)
          fields.append(wrapper)
        }
        const mode = document.createElement("select")
        mode.id = `allocation-mode-${line.key}`
        mode.name = `invoice[position_allocations][${line.key}][mode]`
        mode.add(new Option("Prozent des Positionspreises", "percent"))
        mode.add(new Option("Fester Betrag in Euro", "amount"))
        mode.value = this.positionValues[line.key]?.mode || "percent"
        const value = document.createElement("input")
        value.type = "text"
        value.inputMode = "decimal"
        value.id = `allocation-value-${line.key}`
        value.name = `invoice[position_allocations][${line.key}][value]`
        value.value = formatPrice(this.positionValues[line.key]?.value ?? "0")
        value.required = true
        value.addEventListener("blur", () => { value.value = formatPrice(value.value) })
        const output = document.createElement("output")
        field("Berechnen nach", mode)
        field("Anteil", value)
        element.append(heading, info, fields, output)
        line.element.append(element)
        row = { element, heading, info, mode, value, output }
        this.positionRows.set(line.key, row)
      }
      row.element.hidden = false
      row.heading.textContent = "Anteil dieser Position"
      row.info.hidden = !this.linkedValue
      row.info.textContent = this.linkedValue ? `Noch nicht abgerechnet: ${this.money(line.remaining)}` : ""
      row.mode.disabled = false
      row.value.disabled = false
      row.value.setAttribute("aria-label", `Anteil für Position ${index + 1}`)
      row.mode.setAttribute("aria-label", `Berechnung für Position ${index + 1}`)
    })
  }

}
