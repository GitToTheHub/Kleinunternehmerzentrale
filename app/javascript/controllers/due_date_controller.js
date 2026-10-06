import { Controller } from "@hotwired/stimulus"

// Das Datum "Zahlbar bis" gibt es nur, wenn die Option gewählt ist. Ein deaktiviertes Feld wird nicht gesendet.
export default class extends Controller {
  static targets = ["toggle", "field", "input"]

  connect() {
    this.toggle()
  }

  toggle() {
    const on = this.toggleTarget.checked
    this.fieldTarget.hidden = !on
    this.inputTarget.disabled = !on
    this.inputTarget.required = on
  }
}
