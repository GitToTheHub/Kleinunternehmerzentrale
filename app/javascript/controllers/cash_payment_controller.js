import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["account", "panel", "usage", "split", "amount", "privateHint"]
  static values = { income: Boolean, reversal: Boolean }

  connect() { this.refresh() }

  refresh() {
    const cash = this.accountTarget.value === "cash"
    const split = cash && this.usageTargets.some(input => input.checked && input.value === "split")
    this.panelTarget.hidden = !cash
    const form = this.element.closest("form")
    const kind = form.querySelector('[name="bookkeeping_entry[kind]"]:checked')?.value
    const income = kind ? kind === "income" : this.incomeValue
    this.privateHintTarget.hidden = !income || this.reversalValue || this.accountTarget.value !== "private"
    this.usageTargets.forEach(input => {
      input.disabled = !cash
      input.required = cash
    })
    this.splitTarget.hidden = !split
    this.amountTarget.disabled = !split
    this.amountTarget.required = split
  }
}
