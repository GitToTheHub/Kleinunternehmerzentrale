import { Controller } from "@hotwired/stimulus"
import { formatPrice } from "price_input"

// Parse arithmetic explicitly; never execute the user's input as JavaScript.
export function calculateExpression(expression, { withUnit = false, price = false, hourlyRate } = {}) {
  const source = expression.toLowerCase().replaceAll(",", ".").replaceAll("×", "*").replaceAll("÷", "/").replaceAll("−", "-")
  const tokens = []
  let offset = 0
  while (offset < source.length) {
    if (/\s/.test(source[offset])) { offset++; continue }
    const rest = source.slice(offset)
    const clock = rest.match(/^(\d+):(\d{2})(?!\d)/)
    const number = rest.match(/^(?:\d+(?:\.\d*)?|\.\d+)/)
    if (clock) {
      if (Number(clock[2]) >= 60) throw new Error("Minuten müssen zwischen 00 und 59 liegen.")
      tokens.push({ value: Number(clock[1]) + Number(clock[2]) / 60, unit: "time" })
      offset += clock[0].length
    } else if (number) {
      let value = Number(number[0])
      let valueUnit = "number"
      offset += number[0].length
      const unit = source.slice(offset).match(/^\s*(minuten?|min\.?|stunden?|std\.?|h)\b\.?/)
      if (unit) {
        valueUnit = "time"
        if (unit[1].startsWith("min")) value /= 60
        offset += unit[0].length
      } else {
        const currency = source.slice(offset).match(/^\s*(?:euros?\b|eur\b|€)/)
        if (currency) {
          offset += currency[0].length
          valueUnit = "money"
          if (hourlyRate !== undefined && !price) {
            if (!Number.isFinite(hourlyRate) || hourlyRate <= 0) throw new Error("Bitte gib einen gültigen Preis pro Stunde größer als 0 ein, um Eurobeträge in Stunden umzurechnen.")
            value /= hourlyRate
            valueUnit = "time"
          }
        }
      }
      tokens.push({ value, unit: valueUnit })
    } else if ("+-*/()".includes(source[offset])) {
      tokens.push(source[offset++])
    } else throw new Error("Bitte Zahlen und Rechenzeichen eingeben. Euro, EUR, € sowie Std und min sind möglich.")
  }
  let index = 0
  function factor() {
    const token = tokens[index++]
    if (token && typeof token === "object") return token
    if (token === "+") return factor()
    if (token === "-") { const next = factor(); return { ...next, value: -next.value } }
    if (token === "(") {
      const value = sum()
      if (tokens[index++] !== ")") throw new Error("Bitte die Klammer schließen.")
      return value
    }
    throw new Error("Bitte einen vollständigen Rechenweg eingeben.")
  }
  function product() {
    let value = factor()
    while (["*", "/"].includes(tokens[index])) {
      const operator = tokens[index++]
      const next = factor()
      let unit = value.unit === "number" ? next.unit : value.unit
      if (operator === "*") {
        if (value.unit === "time" && next.unit === "time") throw new Error("Zeiten bitte addieren, nicht miteinander multiplizieren.")
        if ((value.unit === "time" || next.unit === "time") && (price || value.unit === "money" || next.unit === "money")) unit = "money"
      } else if (value.unit === next.unit) unit = "number"
      else if (next.unit !== "number") throw new Error("Diese Einheiten lassen sich so nicht dividieren.")
      value = { value: operator === "*" ? value.value * next.value : value.value / next.value, unit }
    }
    return value
  }
  function sum() {
    let value = product()
    while (["+", "-"].includes(tokens[index])) {
      const operator = tokens[index++]
      const next = product()
      if (value.unit !== next.unit && value.unit !== "number" && next.unit !== "number") throw new Error("Stunden und Geldbeträge können nicht direkt addiert werden. Verrechne die Zeit zuerst mit einem Stundensatz.")
      value = { value: operator === "+" ? value.value + next.value : value.value - next.value, unit: value.unit === "number" ? next.unit : value.unit }
    }
    return value
  }
  const result = sum()
  if (index !== tokens.length) throw new Error("Bitte zwischen den Werten ein Rechenzeichen eingeben.")
  if (!Number.isFinite(result.value)) throw new Error("Diese Berechnung ergibt keinen gültigen Wert.")
  return withUnit ? result : result.value
}

function timeRateSuggestion(expression) {
  const number = String.raw`\d+(?:[.,]\d+)?`
  const time = String.raw`(?:\d+:\d{2}|${number}\s*(?:minuten?|min\.?|stunden?|std\.?|h))`
  const pattern = new RegExp(String.raw`^\s*(${time}(?:\s*[+−-]\s*${time})+)\s*[*×]\s*(${number}\s*(?:euros?|eur|€)?)\s*$`, "i")
  const match = expression.match(pattern)
  return match ? `(${match[1].trim()}) × ${match[2].trim()}` : null
}

export default class extends Controller {
  static targets = ["expression", "help", "result", "apply", "warning", "suggestion", "ratePanel", "rate", "rateLabel", "time", "dialog", "trigger"]
  static values = { field: String }

  opened() {
    this.dialogTarget.showModal()
    const price = this.fieldValue.endsWith("unit_price")
    const hourly = this.element.closest(".invoice-line").querySelector("[data-line-quantity-target=unit]").value === "HUR"
    this.expressionTarget.placeholder = price ? "z. B. 100 + 50 + 25" : hourly ? "z. B. 20 min + 1,5 Std + 1:30" : "z. B. 2 + 3 + 4"
    this.helpTarget.textContent = price
      ? "Beträge in der Rechnungswährung addieren, z. B. 100 + 50 + 25. Bei Euro sind auch Angaben wie 20 Euro + 15 € möglich. Auch andere Grundrechenarten und Klammern sind möglich. Optional kannst du Zeiten mit einem Stundensatz verrechnen, z. B. (30 min + 1 Std) × 60."
      : hourly
      ? "Stunden addieren: 20 min + 20 min + 1,5 Std + 1:30. Zeiten werden in Dezimalstunden umgerechnet. Auch +, −, ×, ÷ und Klammern sind möglich."
      : "Rechne mit +, −, ×, ÷ und Klammern, z. B. (2 + 3) × 4. Für Zeiten kannst du auch 1:30 oder 20 min verwenden; sie werden in Stunden umgerechnet."
    this.calculate()
    this.expressionTarget.focus()
  }

  calculate() {
    this.applyTarget.disabled = true
    this.applyTarget.hidden = false
    this.warningTarget.hidden = true
    this.ratePanelTarget.hidden = true
    if (!this.expressionTarget.value.trim()) { this.resultTarget.textContent = ""; return }
    try {
      const field = document.getElementById(this.fieldValue)
      const precision = this.fieldValue.endsWith("unit_price") ? 2 : 3
      this.suggestedExpression = this.fieldValue.endsWith("unit_price") ? timeRateSuggestion(this.expressionTarget.value) : null
      if (this.suggestedExpression) {
        this.resultTarget.textContent = ""
        this.warningTarget.hidden = false
        this.applyTarget.hidden = true
        this.suggestionTarget.textContent = this.suggestedExpression
        return
      }
      const evaluated = calculateExpression(this.expressionTarget.value, { withUnit: true, price: precision === 2 })
      let calculated = evaluated.value
      const currency = this.element.closest("form").querySelector("#invoice_currency").value
      if (precision === 2 && evaluated.unit === "time") {
        if (calculated < 0) throw new Error("Die Gesamtzeit darf nicht negativ sein.")
        this.ratePanelTarget.hidden = false
        const minutes = Math.round(calculated * 60)
        this.timeTarget.textContent = `Zeit: ${calculated.toLocaleString("de-DE", { maximumFractionDigits: 3 })} Stunden (${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, "0")} Std)`
        this.rateLabelTarget.textContent = `Stundensatz (${currency} pro Stunde)`
        const rate = Number(this.rateTarget.value)
        if (!this.rateTarget.value || !Number.isFinite(rate) || rate < 0) {
          this.resultTarget.textContent = "Bitte gib einen Stundensatz ein, um die Zeit in einen Pauschalpreis umzurechnen."
          return
        }
        calculated *= rate
      }
      this.value = Number(calculated.toFixed(precision))
      if (this.value < Number(field.min || 0) || this.value > (precision === 2 ? 9999999999.99 : 999999999.999)) throw new Error("Das Ergebnis liegt außerhalb des erlaubten Bereichs für dieses Feld.")
      this.resultTarget.textContent = `Ergebnis: ${this.value.toLocaleString("de-DE", { maximumFractionDigits: precision })}`
      const hourly = this.element.closest(".invoice-line").querySelector("[data-line-quantity-target=unit]").value === "HUR"
      const timeExpression = /\d\s*(?:min|std|stunden?|h\b)|\d+:\d{2}/i.test(this.expressionTarget.value)
      if (precision !== 2 && (hourly || timeExpression)) {
        const minutes = Math.round(calculated * 60)
        this.resultTarget.textContent += ` (${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, "0")} Std)`
      }
      if (precision === 2) this.resultTarget.textContent += ` ${currency === "EUR" ? "€" : currency}`
      this.applyTarget.disabled = field.disabled
    } catch (error) { this.resultTarget.textContent = error.message }
  }

  addTimeParentheses() {
    if (!this.suggestedExpression) return
    this.expressionTarget.value = this.suggestedExpression
    this.calculate()
    this.expressionTarget.focus()
  }

  apply(event) {
    event.preventDefault()
    this.calculate()
    if (this.applyTarget.disabled) return
    const field = document.getElementById(this.fieldValue)
    field.value = this.fieldValue.endsWith("unit_price") ? formatPrice(this.value) : String(this.value).replace(".", ",")
    field.dispatchEvent(new Event("input", { bubbles: true }))
    field.dispatchEvent(new Event("change", { bubbles: true }))
    this.close()
    field.focus()
  }

  close() { this.dialogTarget.close() }
}
