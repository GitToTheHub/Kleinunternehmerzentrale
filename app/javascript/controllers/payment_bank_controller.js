import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() { this.update() }

  update() {
    const transfer = document.getElementById("invoice_payment_method")?.value === "transfer"
    this.element.hidden = !transfer
    this.element.querySelectorAll("input").forEach(input => {
      input.disabled = !transfer
      input.required = transfer
    })
  }
}
