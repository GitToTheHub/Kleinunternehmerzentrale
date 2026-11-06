import { Controller } from "@hotwired/stimulus"
import { parsePrice } from "price_input"

// Füllt die Kundenfelder mit den Daten eines gespeicherten Kunden und setzt dessen Stundensatz.
export default class extends Controller {
  static targets = ["picker", "decision", "name", "suggestions", "decisionLegend", "changeList", "dialog", "continueButton"]

  connect() { this.changed() }

  suggest() {
    if (this.filling || !this.hasPickerTarget) return
    const query = this.nameTarget.value.trim().toLocaleLowerCase("de-DE")
    this.matches = Array.from(this.pickerTarget.options).filter(option => option.dataset.values && option.textContent.toLocaleLowerCase("de-DE").includes(query)).slice(0, 8)
    this.activeIndex = -1
    this.suggestionsTarget.replaceChildren()
    this.matches.forEach((option, index) => {
      const item = document.createElement("li")
      item.id = `customer-name-option-${index}`
      item.setAttribute("role", "option")
      item.setAttribute("aria-selected", "false")
      item.textContent = option.textContent
      item.addEventListener("mousedown", event => event.preventDefault())
      item.addEventListener("click", () => this.choose(index))
      this.suggestionsTarget.append(item)
    })
    this.suggestionsTarget.hidden = !this.matches.length
    this.nameTarget.setAttribute("aria-expanded", String(!!this.matches.length))
    this.nameTarget.removeAttribute("aria-activedescendant")
  }

  hideSuggestions() {
    if (!this.hasSuggestionsTarget) return
    this.suggestionsTarget.hidden = true
    this.nameTarget.setAttribute("aria-expanded", "false")
    this.nameTarget.removeAttribute("aria-activedescendant")
  }

  navigate(event) {
    if (event.key === "Escape") { event.preventDefault(); this.hideSuggestions(); return }
    if (!["ArrowDown", "ArrowUp", "Enter"].includes(event.key)) return
    if (this.suggestionsTarget.hidden) {
      if (event.key === "Enter") return
      this.suggest()
    }
    if (!this.matches?.length) return
    if (event.key === "Enter") {
      event.preventDefault()
      if (this.activeIndex >= 0) this.choose(this.activeIndex)
      return
    }
    event.preventDefault()
    this.activeIndex = this.activeIndex < 0
      ? (event.key === "ArrowDown" ? 0 : this.matches.length - 1)
      : (this.activeIndex + (event.key === "ArrowDown" ? 1 : -1) + this.matches.length) % this.matches.length
    Array.from(this.suggestionsTarget.children).forEach((item, index) => item.setAttribute("aria-selected", String(index === this.activeIndex)))
    this.nameTarget.setAttribute("aria-activedescendant", this.suggestionsTarget.children[this.activeIndex].id)
  }

  choose(index) {
    this.pickerTarget.value = this.matches[index].value
    this.fill({ target: this.pickerTarget })
    this.hideSuggestions()
    this.nameTarget.focus()
  }

  review(event) {
    if (event.defaultPrevented) return
    if (this.confirmed) { this.confirmed = false; return }
    this.reviewing = true
    this.changed()
    if (!this.hasChanges) return
    event.preventDefault()
    this.pendingSubmitter = event.submitter
    this.continueButtonTarget.textContent = event.submitter?.dataset.invoicePreview === "true" ? "Weiter zur Vorschau" : "Festschreiben"
    this.dialogTarget.showModal()
  }

  confirmReview() {
    const selected = this.decisionTarget.querySelector("input:checked")
    if (!selected) { this.decisionTarget.querySelector("input").reportValidity(); return }
    this.dialogTarget.close()
    this.confirmed = true
    this.element.requestSubmit(this.pendingSubmitter)
  }

  cancelReview() {
    this.dialogTarget.close()
    this.pendingSubmitter = null
    this.reviewing = false
    this.changed()
  }

  changed(event) {
    if (event && event.target?.name !== "invoice[customer_update_mode]") this.reviewing = false
    if (this.filling || !this.hasDecisionTarget) return
    const option = this.hasPickerTarget ? this.pickerTarget.selectedOptions[0] : null
    const changes = []
    const labels = JSON.parse(this.decisionTarget.dataset.changeLabels || "{}")
    const describe = (key, stored, value) => {
      const display = entry => entry == null || entry === "" ? "nicht hinterlegt" : key === "hourly_rate" ? `${Number(String(entry).replace(",", ".")).toLocaleString("de-DE", { style: "currency", currency: "EUR" })} pro Stunde` : key === "payment_due_days" ? `${entry} Tage` : String(entry)
      changes.push({ key, text: `${labels[key] || key}: ${display(stored)} → ${display(value)}` })
    }
    if (option?.dataset.values) {
      const fieldKeys = { buyer_hourly_rate: "hourly_rate", buyer_name: "name", buyer_abbreviation: "invoice_abbreviation", buyer_contact_name: "contact_name", buyer_email: "email", buyer_street: "street", buyer_postal_code: "postal_code", buyer_city: "city", buyer_country: "country", buyer_leitweg_id: "leitweg_id", payment_terms: "payment_terms" }
      Object.entries(JSON.parse(option.dataset.values)).forEach(([name, stored]) => {
        const field = document.getElementById(`invoice_${name}`)
        let value = field?.value ?? ""
        if (name === "buyer_abbreviation") value = value.trim().toUpperCase()
        if (name === "buyer_hourly_rate" && value !== "" && stored != null && Number(value.replace(",", ".")) === Number(stored)) return
        if (value !== String(stored ?? "")) describe(fieldKeys[name] || name, stored, value)
      })
      const issued = document.getElementById("invoice_issued_on").value
      const due = document.getElementById("invoice_payment_due_on").value
      const days = due && issued ? (Date.parse(`${due}T00:00:00Z`) - Date.parse(`${issued}T00:00:00Z`)) / 86400000 : ""
      if (String(days) !== String(option.dataset.dueDays ?? "")) describe("payment_due_days", option.dataset.dueDays, days)
      const hourlyRows = Array.from(this.element.querySelectorAll("[data-invoice-lines-target='row']"))
        .filter(row => row.querySelector("[name$='[unit_code]']")?.value === "HUR" && row.querySelector("[name$='[_destroy]']")?.value !== "1")
      const rates = [...new Set(hourlyRows.map(row => parsePrice(row.querySelector("[name$='[unit_price]']").value)).filter(value => value > 0))]
      const rate = rates.length === 1 ? rates[0] : null
      if (!document.getElementById("invoice_buyer_hourly_rate") && rate && (this.element.querySelector("[name='invoice[currency]']")?.value || "EUR") === "EUR" && rate !== Number(option.dataset.hourlyRate)) describe("hourly_rate", option.dataset.hourlyRate, rate)
    }
    const changed = changes.length > 0
    this.hasChanges = changed
    if (this.hasDecisionLegendTarget) this.decisionLegendTarget.textContent = changes.length === 1 && changes[0].key === "hourly_rate" ? "Stundensatz für diesen Kunden speichern?" : "Änderungen für künftige Rechnungen speichern?"
    if (this.hasChangeListTarget) {
      this.changeListTarget.replaceChildren(...changes.map(change => {
        const item = document.createElement("li")
        item.textContent = change.text
        return item
      }))
    }
    this.decisionTarget.hidden = !changed || !this.reviewing
    this.decisionTarget.querySelectorAll("input").forEach(input => {
      input.disabled = !changed
      input.required = changed && !!this.reviewing
    })
  }

  fill({ target }) {
    const option = target.selectedOptions[0]
    if (this.hasDecisionTarget) this.decisionTarget.querySelectorAll("input").forEach(input => { input.checked = false })
    if (!option || !option.dataset.values) { this.changed(); return }
    this.filling = true

    Object.entries(JSON.parse(option.dataset.values)).forEach(([name, value]) => {
      const field = document.getElementById(`invoice_${name}`)
      if (field) {
        field.value = name === "buyer_hourly_rate" && value != null && value !== ""
          ? Number(value).toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2, useGrouping: false })
          : value ?? ""
        field.dispatchEvent(new Event("input", { bubbles: true }))
        field.dispatchEvent(new Event("change", { bubbles: true }))
      }
    })

    this.applyPaymentDeadline(option.dataset.dueDays)
    this.applyHourlyRate(option.dataset.hourlyRate || target.dataset.defaultRate || "")
    this.filling = false
    this.changed()
    this.hideSuggestions()
  }

  // Leer bedeutet: keine Zahlungsfrist. Sonst wird das Datum aus dem Rechnungsdatum berechnet.
  applyPaymentDeadline(days) {
    const due = document.getElementById("invoice_payment_due_on")
    const issuedValue = document.getElementById("invoice_issued_on")?.value
    const issued = issuedValue ? new Date(`${issuedValue}T00:00:00Z`) : null
    if (!due) return

    due.value = ""
    if (days !== "" && issued) {
      issued.setUTCDate(issued.getUTCDate() + Number(days))
      due.value = issued.toISOString().slice(0, 10)
    }
    due.dispatchEvent(new Event("change", { bubbles: true }))
  }

  defaultRateChanged({ target }) {
    const value = target.value.trim().replace(/\./g, target.value.includes(",") ? "" : ".").replace(",", ".")
    const rate = value === "" ? "" : Number(value)
    if (rate !== "" && (!Number.isFinite(rate) || rate < 0)) return
    const customerRate = document.getElementById("invoice_buyer_hourly_rate")
    if (customerRate) customerRate.placeholder = rate === "" ? "" : Number(rate).toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
    if (this.hasPickerTarget) {
      this.pickerTarget.dataset.defaultRate = rate
    }
    if (document.getElementById("invoice_buyer_hourly_rate")?.value) return
    this.applyHourlyRate(rate)
  }

  customerRateChanged({ target }) {
    const value = target.value.trim().replace(/\./g, target.value.includes(",") ? "" : ".").replace(",", ".")
    const general = document.getElementById("invoice_seller_hourly_rate")?.value || ""
    const fallback = general.trim().replace(/\./g, general.includes(",") ? "" : ".").replace(",", ".")
    const rate = value === "" ? fallback : Number(value)
    if (rate !== "" && (!Number.isFinite(Number(rate)) || Number(rate) < 0)) return
    this.applyHourlyRate(rate)
  }

  applyHourlyRate(rate) {
    const form = this.element.closest("form")
    const previous = form.dataset.hourlyRate || ""
    form.dataset.hourlyRate = rate
    window.dispatchEvent(new CustomEvent("hourly-rate:changed", { detail: { previous, rate } }))
  }
}
