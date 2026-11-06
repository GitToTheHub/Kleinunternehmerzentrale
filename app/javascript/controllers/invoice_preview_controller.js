import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "frame", "heading"]

  open(event) {
    this.opener = document.activeElement
    const url = new URL(event.detail.url, window.location.href)
    url.searchParams.set("embedded", "1")
    this.frameTarget.src = url.href
    this.startedOnBackdrop = false
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
    this.headingTarget.focus()
  }

  loaded() {
    this.frameTarget.contentDocument?.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        event.preventDefault()
        this.close()
      }
    })
  }

  close() {
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  closed() {
    this.frameTarget.removeAttribute("src")
    this.opener?.focus()
  }

  startBackdrop(event) { this.startedOnBackdrop = this.isBackdrop(event) }

  closeOnBackdrop(event) {
    const close = this.startedOnBackdrop && this.isBackdrop(event)
    this.startedOnBackdrop = false
    if (close) this.close()
  }

  isBackdrop(event) {
    if (event.target !== this.dialogTarget) return false
    const rect = this.dialogTarget.getBoundingClientRect()
    return event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom
  }
}
