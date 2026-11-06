import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["method", "daysPanel", "monthsPanel", "basisPanel", "deductionMethod", "professionPanel", "childcarePanel", "childcareList", "childcareTemplate", "childcareRow"]

  connect() { this.index = Date.now(); this.refresh() }

  refresh() {
    const method = this.methodTarget.value
    this.panel(this.daysPanelTarget, method === "days")
    this.panel(this.monthsPanelTarget, method === "annual")
    this.panel(this.basisPanelTarget, method !== "none")
    const daycare = this.deductionMethodTarget.value === "daycare"
    this.professionPanelTargets.forEach(panel => { panel.hidden = panel.dataset.method !== this.deductionMethodTarget.value })
    this.panel(this.childcarePanelTarget, daycare)
    this.childcareRowTargets.forEach(row => {
      const reserve = row.querySelector("[data-childcare-kind]").value === "reserved"
      row.querySelectorAll("[data-childcare-regular]").forEach(panel => this.panel(panel, daycare && !reserve))
      row.querySelectorAll("[data-childcare-reserved]").forEach(panel => this.panel(panel, daycare && reserve))
    })
  }

  addChildcare() {
    this.childcareListTarget.insertAdjacentHTML("beforeend", this.childcareTemplateTarget.innerHTML.replaceAll("NEW_ROW", String(this.index++)))
    this.refresh()
  }

  removeChildcare(event) {
    event.currentTarget.closest("[data-euer-expense-policy-target='childcareRow']").remove()
  }

  panel(element, active) {
    element.hidden = !active
    element.querySelectorAll("input, textarea, select").forEach(input => {
      input.disabled = !active
      input.required = active
    })
  }
}
