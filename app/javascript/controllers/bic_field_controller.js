import { Controller } from "@hotwired/stimulus"

// Die BIC wird nur gebraucht, wenn die Kundin oder der Kunde außerhalb des SEPA-Raums sitzt (SWIFT-Zahlung).
export default class extends Controller {
  static values = { sepa: Array }

  update({ target }) {
    if (target.id !== "invoice_buyer_country") return

    this.element.hidden = this.sepaValue.includes(target.value)
  }
}
