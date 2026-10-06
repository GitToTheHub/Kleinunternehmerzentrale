import { Controller } from "@hotwired/stimulus"

// Schaltet das Formular zwischen Kleinunternehmer und Regelbesteuerung um.
// Die Anzeige läuft über CSS (data-tax-mode am Formular), die Summen über ein Fensterereignis.
export default class extends Controller {
  change(event) {
    this.element.dataset.taxMode = event.target.value
    window.dispatchEvent(new CustomEvent("tax-mode:changed"))
  }
}
