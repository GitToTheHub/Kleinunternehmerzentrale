import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  saveShortcut(event) {
    if (event.key.toLowerCase() !== "s" || !(event.ctrlKey || event.metaKey) || event.altKey || event.shiftKey) return
    event.preventDefault()
    if (!event.repeat) this.element.requestSubmit()
  }
}
