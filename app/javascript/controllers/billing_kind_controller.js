import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["heading", "description", "kind", "serviceLabel", "serviceEndLabel", "serviceHint", "serviceEndHint", "issuedOnHint"]

  connect() {
    this.issuedOnHints = JSON.parse(this.issuedOnHintTarget.dataset.hints)
    this.serviceDateTexts = JSON.parse(this.serviceLabelTarget.dataset.texts)
    this.update()
  }

  update() {
    const selected = this.kindTargets.find((radio) => radio.checked)
    const kind = selected?.value || "regular"
    if (this.hasHeadingTarget && this.headingTarget.dataset.correction !== "true") {
      const labels = { regular: "Rechnung", advance: "Anzahlungsrechnung", progress: "Abschlagsrechnung", final: "Schlussrechnung" }
      this.headingTarget.textContent = `${labels[kind]} erstellen`
    }
    if (this.hasDescriptionTarget) {
      const hints = JSON.parse(this.descriptionTarget.dataset.hints)
      this.descriptionTarget.textContent = hints[kind] || hints.regular
    }
    this.issuedOnHintTarget.textContent = this.issuedOnHints[kind] || this.issuedOnHints.regular
    const serviceTexts = this.serviceDateTexts[kind === "advance" ? "advance" : "regular"]
    this.serviceLabelTarget.textContent = serviceTexts.from
    this.serviceEndLabelTarget.textContent = serviceTexts.to
    this.serviceHintTarget.textContent = serviceTexts.from_hint
    this.serviceEndHintTarget.textContent = serviceTexts.to_hint
  }
}
