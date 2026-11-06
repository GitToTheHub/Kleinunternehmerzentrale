import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["name", "address", "taxIdentifier", "contact", "hourlyRate"]

  connect() {
    this.refresh()
  }

  refresh() {
    const value = (name) => this.element.querySelector(`[name="invoice[${name}]"]`)
    const text = (name) => value(name)?.value.trim() || ""
    const country = value("seller_country")
    const address = [
      text("seller_street"),
      [text("seller_postal_code"), text("seller_city")].filter(Boolean).join(" "),
      country?.selectedOptions[0]?.textContent.trim()
    ].filter(Boolean).join(", ")
    const contact = [text("seller_email"), text("seller_phone")].filter(Boolean).join(" · ")

    this.nameTarget.textContent = text("seller_name") || "Eigene Angaben"
    this.addressTarget.textContent = address || "Adresse noch nicht angegeben"
    this.taxIdentifierTarget.textContent = text("seller_tax_identifier") || "Steuernummer oder USt-ID noch nicht angegeben"
    this.contactTarget.textContent = contact || "Keine Kontaktdaten angegeben"
    const input = text("seller_hourly_rate")
    const rate = Number(input.replace(/\./g, input.includes(",") ? "" : ".").replace(",", "."))
    this.hourlyRateTarget.textContent = input && Number.isFinite(rate) && rate >= 0
      ? `Allgemeiner Stundensatz: ${rate.toLocaleString("de-DE", { style: "currency", currency: "EUR" })} pro Stunde`
      : "Kein allgemeiner Stundensatz hinterlegt"
  }
}
