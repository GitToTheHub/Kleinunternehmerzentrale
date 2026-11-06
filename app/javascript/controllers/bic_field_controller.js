import { Controller } from "@hotwired/stimulus"

// Die BIC wird nur gebraucht, wenn die Kundin oder der Kunde außerhalb des SEPA-Raums sitzt (SWIFT-Zahlung).
export default class extends Controller {
  static values = { sepa: Array }

  connect() { this.update() }

  update() {
    const transfer = document.getElementById("invoice_payment_method")?.value === "transfer"
    this.element.hidden = !transfer || this.sepaValue.includes(document.getElementById("invoice_buyer_country")?.value)
    this.element.querySelectorAll("input").forEach(input => { input.disabled = this.element.hidden })
  }
}
