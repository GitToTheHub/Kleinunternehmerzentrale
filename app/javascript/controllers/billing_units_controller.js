import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["unit", "save", "error", "status", "popover"]
  static values = { url: String, options: Object }

  connect() {
    if (window.location.hash === "#billing-units") this.popoverTarget.showPopover()
  }

  async save() {
    const units = this.unitTargets.filter(input => input.checked).map(input => input.value)
    this.errorTarget.textContent = ""
    this.statusTarget.textContent = ""
    if (!units.length) {
      this.errorTarget.textContent = "Wähle mindestens eine gültige Einheit."
      return
    }
    this.saveTarget.disabled = true
    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" },
        body: JSON.stringify({ workflow: { units } })
      })
      const result = await response.json()
      if (!response.ok) throw new Error()
      const panel = this.element.closest('[data-controller="invoice-lines"]')
      const update = (select, template = false) => {
        const previous = select.value
        const available = Object.entries(this.optionsValue).filter(([code]) => result.units.includes(code))
        select.replaceChildren(...available.map(([code, label]) => new Option(label, code)))
        select.value = !template && result.units.includes(previous) ? previous : result.units[0]
        if (!template && select.value !== previous) select.dispatchEvent(new Event("change", { bubbles: true }))
      }
      panel.querySelectorAll('select[data-line-quantity-target="unit"]').forEach(select => update(select))
      panel.querySelectorAll("template").forEach(template => template.content.querySelectorAll('select[data-line-quantity-target="unit"]').forEach(select => update(select, true)))
      this.popoverTarget.hidePopover()
      this.statusTarget.textContent = "Einheiten gespeichert. Die Auswahl wurde aktualisiert."
    } catch {
      this.errorTarget.textContent = "Die Einheiten konnten nicht gespeichert werden. Bitte versuche es erneut."
    } finally {
      this.saveTarget.disabled = false
    }
  }
}
