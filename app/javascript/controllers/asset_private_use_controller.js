import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["mode", "manual", "amount"]
  connect() { this.refresh() }
  refresh() {
    const manual = this.modeTarget.value === "manual"
    this.manualTarget.hidden = !manual
    this.amountTarget.disabled = !manual
    if (!manual) this.amountTarget.value = ""
  }
}
