import { Controller } from "@hotwired/stimulus"

// Zeigt das Enddatum nur, wenn ein Leistungszeitraum gewählt ist.
export default class extends Controller {
  static targets = ["choice", "until", "startLabel"]

  connect() {
    this.toggle()
  }

  toggle() {
    const period = this.choiceTargets.find((radio) => radio.checked)?.value === "true"
    this.untilTarget.hidden = !period
    this.untilTarget.querySelector("input").required = period
    this.startLabelTarget.textContent = period ? "Leistung von" : "Leistungsdatum"
  }
}
