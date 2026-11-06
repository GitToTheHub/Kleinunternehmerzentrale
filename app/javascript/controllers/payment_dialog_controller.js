import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "content", "title"]

  async open(event) {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    event.preventDefault()
    const link = event.currentTarget
    const url = new URL(link.href)
    url.searchParams.set("payment_popup", "1")
    try {
      const response = await fetch(url, { headers: { Accept: "text/html" } })
      if (!response.ok || response.redirected) return window.location.assign(link.href)
      this.contentTarget.innerHTML = await response.text()
      this.titleTarget.textContent = this.contentTarget.querySelector("[data-payment-title]").dataset.paymentTitle
      this.dialogTarget.showModal()
    } catch {
      window.location.assign(link.href)
    }
  }

  close() {
    if (this.hasDialogTarget) this.dialogTarget.close()
  }

  async submit(event) {
    event.preventDefault()
    const form = event.target
    const button = event.submitter
    if (button?.disabled) return
    if (button) button.disabled = true
    try {
      const headers = { Accept: "application/json" }
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      if (token) headers["X-CSRF-Token"] = token
      const response = await fetch(form.action, {
        method: "POST",
        body: new FormData(form),
        headers
      })
      if (response.ok) {
        const destination = new URL((await response.json()).location, window.location.href)
        if (destination.pathname === window.location.pathname && destination.search === window.location.search) {
          window.history.replaceState(null, "", destination)
          window.location.reload()
        } else {
          window.location.assign(destination)
        }
      } else if (response.status === 422) {
        this.contentTarget.innerHTML = await response.text()
        this.contentTarget.querySelector("[role=alert]")?.setAttribute("tabindex", "-1")
        this.contentTarget.querySelector("[role=alert]")?.focus()
      } else {
        this.showError()
      }
    } catch {
      this.showError()
    } finally {
      if (button) button.disabled = false
    }
  }

  showError() {
    let error = this.contentTarget.querySelector("[role=alert]")
    if (!error) {
      error = document.createElement("p")
      error.className = "flash-message flash-message--alert"
      error.setAttribute("role", "alert")
      this.contentTarget.prepend(error)
    }
    error.textContent = "Die Zahlung konnte nicht bestätigt werden. Bitte versuche es erneut."
  }
}
