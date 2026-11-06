import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["usageRows", "usageTemplate", "origin", "method", "disposal", "linearField", "gwgField", "purchaseField", "withdrawalField", "recognitionField", "scheduleField", "rows", "template"]

  connect() { this.refresh() }

  refresh() {
    const method = this.methodTarget.value
    this.show(this.linearFieldTarget, ["linear", "manual"].includes(method))
    this.show(this.gwgFieldTarget, method === "gwg")
    // Keep saved rows visible when changing the method, so they can be removed
    // explicitly instead of silently surviving behind a hidden section.
    this.show(this.scheduleFieldTarget, true, false)
    if (method === "manual") this.scheduleFieldTarget.open = true
    this.purchaseFieldTargets.forEach(field => this.show(field, this.originTarget.value === "purchase"))
    this.withdrawalFieldTargets.forEach(field => this.show(field, this.disposalTarget.value === "withdrawal"))
    this.show(this.recognitionFieldTarget, method === "none" && this.disposalTarget.value === "sale")
  }

  addUsageYear() {
    const key = `${Date.now()}${this.usageRowsTarget.children.length}`
    this.usageRowsTarget.insertAdjacentHTML("beforeend", this.usageTemplateTarget.innerHTML.replaceAll("NEW_USAGE", key))
  }

  addYear() {
    const key = `${Date.now()}${this.rowsTarget.children.length}`
    this.rowsTarget.insertAdjacentHTML("beforeend", this.templateTarget.innerHTML.replaceAll("NEW_ROW", key))
  }

  show(field, visible, clear = true) {
    field.hidden = !visible
    if (!visible && clear) {
      for (const input of field.querySelectorAll("input, select")) {
        if (input.name.endsWith("[input_vat]") || input.name.endsWith("[withdrawal_vat]")) input.value = "0"
        else if (input.name.endsWith("[payment_account]")) input.value = "business"
        else input.value = ""
      }
    }
  }
}
