import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["year", "position", "sourceNote"]

  connect() { this.refresh() }

  refresh() {
    const year = this.yearTarget.value
    this.sourceNoteTargets.forEach(element => { element.textContent = JSON.parse(element.dataset.notes)[year] || `Für ${year} sind keine geprüften Formulardaten hinterlegt.` })
    for (const option of this.positionTarget.options) {
      if (!option.value) continue
      const labels = JSON.parse(option.dataset.labels)
      option.disabled = !labels[year]
      option.hidden = !labels[year]
      option.textContent = labels[year] || "Für dieses Steuerjahr nicht vorgesehen"
      if (option.disabled && option.selected) this.positionTarget.value = ""
    }
  }
}
