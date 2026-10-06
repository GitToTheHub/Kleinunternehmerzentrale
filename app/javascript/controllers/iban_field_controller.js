import { Controller } from "@hotwired/stimulus"

// Prüft die IBAN schon beim Tippen: Länge je Land und Prüfsumme (Modulo 97), wie auf dem Server.
export default class extends Controller {
  static targets = ["input", "status"]
  static values = { lengths: Object }

  connect() { this.check() }

  check() {
    const iban = this.inputTarget.value.replace(/\s+/g, "").toUpperCase()
    if (!iban) return this.show("", "")

    const expected = this.lengthsValue[iban.slice(0, 2)]
    if (expected && iban.length < expected) return this.show("", "")
    if (expected && iban.length > expected) {
      return this.show("error", `Zu lang: ${iban.slice(0, 2)}-IBANs haben ${expected} Zeichen.`)
    }
    if (!/^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$/.test(iban)) {
      return iban.length < 15 ? this.show("", "") : this.show("error", "Das sieht nicht wie eine IBAN aus.")
    }
    this.show(this.valid(iban) ? "ok" : "error", this.valid(iban) ? "✓ IBAN ist formal korrekt." : "Prüfsumme stimmt nicht, bitte prüfe auf Tippfehler.")
  }

  valid(iban) {
    const digits = (iban.slice(4) + iban.slice(0, 4)).replace(/[A-Z]/g, (c) => c.charCodeAt(0) - 55)
    let rest = 0
    for (const d of digits) rest = (rest * 10 + Number(d)) % 97
    return rest === 1
  }

  show(state, text) {
    this.statusTarget.dataset.state = state
    this.statusTarget.textContent = text
  }
}
