import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["paid", "details", "foreignAmount"]

  connect() { this.update() }

  update() {
    const paid = this.paidTarget.checked
    const foreign = this.element.querySelector("#invoice_currency").value !== "EUR"
    this.detailsTarget.hidden = !paid
    this.foreignAmountTarget.hidden = !foreign
    this.detailsTarget.querySelectorAll("input, select").forEach(input => {
      const enabled = paid && (!this.foreignAmountTarget.contains(input) || foreign)
      input.disabled = !enabled
      input.required = enabled
    })
  }
}
