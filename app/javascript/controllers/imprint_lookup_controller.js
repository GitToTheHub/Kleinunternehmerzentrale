import { Controller } from "@hotwired/stimulus"

const FIELD_LABELS = {
  buyer_name: "Name/Firma",
  buyer_contact_name: "Inhaber/in oder Ansprechpartner/in",
  buyer_email: "E-Mail-Adresse",
  buyer_street: "Straße und Hausnummer",
  buyer_postal_code: "Postleitzahl",
  buyer_city: "Ort",
  buyer_country: "Land"
}

export default class extends Controller {
  static targets = ["panel", "domain", "status", "popover", "button", "buttonLabel", "spinner", "results", "resultFields", "resultHeading"]
  static values = { url: String }

  disconnect() {
    this.request?.abort()
    this.entries = null
  }

  submitOnEnter(event) {
    if (event.key !== "Enter") return

    event.preventDefault()
    this.lookup()
  }

  async lookup() {
    if (this.loading) return

    this.resetResult()
    const domain = this.domainTarget.value.trim()
    if (!domain) {
      this.showError("Gib zuerst eine Domain oder eine vollständige Seitenadresse ein.")
      return
    }

    this.statusTarget.textContent = "Impressum wird abgerufen …"
    this.statusTarget.removeAttribute("data-error")
    this.setLoading(true)
    const request = this.request = new AbortController()

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content ||
            this.element?.closest("form")?.querySelector("input[name='authenticity_token']")?.value || "",
          "Accept": "application/json"
        },
        body: JSON.stringify({ domain }),
        signal: request.signal,
      })
      const result = await response.json()
      if (request.signal.aborted) return
      if (!response.ok) throw new Error(result.error || "Die Impressumsseite konnte nicht abgerufen werden.")

      const entries = Object.keys(FIELD_LABELS).filter(field => typeof result[field] === "string" && result[field].trim()).map(field => [field, result[field].trim()])
      if (entries.length === 0) throw new Error("Es konnten keine passenden Angaben erkannt werden.")

      this.entries = entries
      this.renderResult(entries)
    } catch (error) {
      if (!request.signal.aborted) this.showError(error.message || "Die Impressumsseite konnte nicht abgerufen werden.")
    } finally {
      this.setLoading(false)
    }
  }

  resetResult() {
    this.entries = null
    if (this.hasResultsTarget) this.resultsTarget.hidden = true
    this.statusTarget.textContent = ""
    this.statusTarget.removeAttribute("data-error")
  }

  renderResult(entries) {
    const rows = entries.map(([field, value]) => {
      const row = document.createElement("div")
      const label = document.createElement("dt")
      const content = document.createElement("dd")
      label.textContent = FIELD_LABELS[field]
      content.textContent = value
      row.append(label, content)
      return row
    })
    this.resultFieldsTarget.replaceChildren(...rows)
    this.resultsTarget.hidden = false
    this.statusTarget.textContent = "Daten ermittelt. Bitte prüfen und anschließend übernehmen."
    this.resultHeadingTarget.focus()
  }

  accept() {
    if (this.loading || !this.entries?.length) return
    this.apply(this.entries)
    this.entries = null
    this.resultsTarget.hidden = true
    this.popoverTarget.hidePopover()
  }

  setLoading(loading) {
    this.loading = loading
    this.buttonTarget.disabled = loading
    this.domainTarget.readOnly = loading
    this.spinnerTarget.hidden = !loading
    this.buttonLabelTarget.textContent = loading ? "Daten werden ermittelt …" : "Daten ermitteln"
    this.panelTarget.setAttribute("aria-busy", loading.toString())
  }

  apply(entries) {
    entries.forEach(([field, value]) => {
      const input = document.getElementById(`invoice_${field}`)
      if (!input) return
      if (input.tagName === "SELECT" && !Array.from(input.options).some(option => option.value === value)) return
      input.value = value
      if (field !== "buyer_street") input.dispatchEvent(new Event("input", { bubbles: true }))
      input.dispatchEvent(new Event("change", { bubbles: true }))
    })

  }

  showError(message) {
    this.statusTarget.textContent = message
    this.statusTarget.dataset.error = "true"
  }
}
