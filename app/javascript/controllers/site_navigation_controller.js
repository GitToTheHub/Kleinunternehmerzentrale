import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle"]

  toggle() {
    const expanded = this.toggleTarget.getAttribute("aria-expanded") !== "true"
    this.toggleTarget.setAttribute("aria-expanded", String(expanded))
    this.toggleTarget.setAttribute("aria-label", expanded ? "Menü schließen" : "Menü öffnen")
  }

  close(event) {
    if (event?.key === "Escape" && this.toggleTarget.getAttribute("aria-expanded") === "true") {
      event.preventDefault()
      this.toggleTarget.focus()
    }
    this.toggleTarget.setAttribute("aria-expanded", "false")
    this.toggleTarget.setAttribute("aria-label", "Menü öffnen")
  }

  outside(event) {
    if (!this.element.contains(event.target)) this.close()
  }
}
