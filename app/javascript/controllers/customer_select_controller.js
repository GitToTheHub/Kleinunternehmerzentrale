import { Controller } from "@hotwired/stimulus"

// Füllt die Kundenfelder mit den Daten eines gespeicherten Kunden und setzt dessen Stundensatz.
export default class extends Controller {
  fill({ target }) {
    const option = target.selectedOptions[0]
    if (!option || !option.dataset.values) return

    Object.entries(JSON.parse(option.dataset.values)).forEach(([name, value]) => {
      const field = document.getElementById(`invoice_${name}`)
      if (field) field.value = value ?? ""
    })

    this.applyPaymentDeadline(option.dataset.dueDays)
    this.applyHourlyRate(option.dataset.hourlyRate || target.dataset.defaultRate || "")
  }

  // Leer bedeutet: keine Zahlungsfrist. Sonst wird das Datum aus dem Rechnungsdatum berechnet.
  applyPaymentDeadline(days) {
    const toggle = document.getElementById("due_date_enabled")
    const due = document.getElementById("invoice_payment_due_on")
    const issued = document.getElementById("invoice_issued_on").valueAsDate
    if (!toggle || !due) return

    toggle.checked = days !== ""
    if (days !== "" && issued) {
      issued.setDate(issued.getDate() + Number(days))
      due.value = issued.toISOString().slice(0, 10)
    }
    toggle.dispatchEvent(new Event("input", { bubbles: true }))
  }

  applyHourlyRate(rate) {
    const form = this.element.closest("form")
    const previous = form.dataset.hourlyRate || ""
    form.dataset.hourlyRate = rate
    window.dispatchEvent(new CustomEvent("hourly-rate:changed", { detail: { previous, rate } }))
  }
}
