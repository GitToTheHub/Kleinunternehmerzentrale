import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row", "hint", "sum"]

  connect() { this.update() }

  update(event) {
    if (event?.target === this.element) return
    const form = this.element.closest("form")
    const final = form.querySelector('[name="invoice[billing_kind]"]:checked')?.value === "final"
    const customer = form.querySelector('[name="invoice[customer_id]"]')?.value || ""
    this.element.hidden = !final
    let available = 0
    let amount = 0
    let changed = false
    this.rowTargets.forEach(row => {
      const sameCustomer = customer !== "" && row.dataset.customerId === customer
      row.hidden = !sameCustomer
      const input = row.querySelector("input")
      input.disabled = !final || !sameCustomer
      if (!sameCustomer && input.checked) { input.checked = false; changed = true }
      if (sameCustomer) available++
      if (!input.disabled && input.checked) amount += Number(row.dataset.amount)
    })
    this.hintTarget.textContent = !customer ? "Wähle zuerst einen gespeicherten Kunden, um seine bezahlten Anzahlungen auszuwählen." : available ? "Wähle die bezahlten Teilrechnungen für diesen Auftrag. Zusammengehörige Teilrechnungen werden gemeinsam berücksichtigt." : "Keine weiteren bezahlten und noch nicht angerechneten direkten Teilrechnungen für diesen Kunden verfügbar."
    this.sumTarget.hidden = !available
    this.sumTarget.textContent = `Ausgewählte Zahlungen: ${amount.toLocaleString("de-DE", { style: "currency", currency: "EUR" })}. Diese werden in der Vorschau und Schlussrechnung abgezogen.`
    if (changed) this.element.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
