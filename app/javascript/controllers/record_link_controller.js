import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["link"]

  open(event) {
    const selection = window.getSelection()
    if (selection && !selection.isCollapsed && selection.containsNode(this.element, true)) {
      event.preventDefault()
      return
    }

    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    if (event.target.closest("a, button, input, select, textarea, label, [contenteditable]")) return

    this.linkTarget.click()
  }
}
