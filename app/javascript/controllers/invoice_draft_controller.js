import { Controller } from "@hotwired/stimulus"

const AUTOSAVE_HINT = "Entwurf wird automatisch gespeichert"

export default class extends Controller {
  static targets = ["status", "draftId", "leave", "discardButton", "discardLabel", "discardIcon", "cancelIcon"]
  static values = { url: String, deleteUrl: String, persisted: Boolean, content: Boolean }

  connect() {
    this.statusTarget.textContent = AUTOSAVE_HINT
    this.hasContent = this.persistedValue || this.contentValue
    this.updateActions()
    if (this.contentValue && !this.persistedValue) this.schedule()
    this.saveBeforeLeaving = () => {
      if (this.pending && !this.skipSaveOnLeave) this.save(true)
    }
    window.addEventListener("pagehide", this.saveBeforeLeaving)
  }

  disconnect() {
    window.removeEventListener("pagehide", this.saveBeforeLeaving)
    if (this.pending && !this.skipSaveOnLeave) this.save(true)
    else this.stopPendingSave()
  }

  schedule(event) {
    if (this.discarding) return
    if (event?.target.closest(".imprint-lookup")) return

    clearTimeout(this.timer)
    this.pending = true
    this.hasContent = true
    this.updateActions()
    if (this.statusTarget.textContent !== "Ungespeicherte Änderungen") this.statusTarget.textContent = "Ungespeicherte Änderungen"
    this.timer = setTimeout(() => this.save(), 1000)
  }

  async saveShortcut(event) {
    if (event.key.toLowerCase() !== "s" || !(event.ctrlKey || event.metaKey) || event.altKey || event.shiftKey) return
    event.preventDefault()
    if (event.repeat || this.leaving || this.discarding || this.skipSaveOnLeave || !this.hasContent) return
    if (await this.flush()) this.statusTarget.textContent = "Entwurf gespeichert"
  }

  async prepareSubmit(event) {
    if (this.discarding) {
      event.preventDefault()
      return
    }
    if (event.defaultPrevented) return
    if (event.submitter?.dataset.invoicePreview === "true") {
      if (this.preparingPreview) {
        event.preventDefault()
        return
      }
      event.preventDefault()
      this.preparingPreview = true
      try {
        if (!await this.flush() || (!this.previewUrl && !await this.save()) || !await this.flush()) return
        this.dispatch("preview", { detail: { url: this.previewUrl } })
      } finally {
        this.preparingPreview = false
      }
      return
    }

    this.skipSaveOnLeave = true
    this.stopPendingSave()
  }

  async discard(event) {
    event.preventDefault()
    if (this.leaving) return
    if ((this.hasContent || this.persistedValue) && !window.confirm("Entwurf wirklich verwerfen? Die gespeicherten Angaben gehen dabei verloren.")) return
    this.leaving = true
    this.discarding = true
    this.skipSaveOnLeave = true
    clearTimeout(this.timer)
    this.pending = false

    // Let the first save finish so its workspace cookie and draft ID are available.
    if (this.savePromise) await this.savePromise
    try {
      if (this.hasContent || this.persistedValue) {
        const response = await fetch(this.deleteUrlValue, {
          method: "DELETE", body: new FormData(this.element), headers: { Accept: "application/json" },
        })
        if (!response.ok) throw new Error()
      }
      window.location.assign(this.leaveTarget.href)
    } catch (error) {
      this.leaving = false
      this.discarding = false
      this.skipSaveOnLeave = false
      this.pending = true
      this.statusTarget.textContent = "Entwurf konnte nicht gelöscht werden"
      this.updateActions()
    }
  }

  updateActions() {
    if (this.hasLeaveTarget) {
      this.leaveTarget.hidden = !this.hasContent
    }
    if (this.hasDiscardIconTarget) this.discardIconTarget.hidden = !this.hasContent
    if (this.hasCancelIconTarget) this.cancelIconTarget.hidden = !!this.hasContent
    if (this.hasDiscardLabelTarget) this.discardLabelTarget.textContent = this.hasContent ? "Verwerfen" : "Abbrechen"
    if (this.hasDiscardButtonTarget) {
      this.discardButtonTarget.classList.toggle("button--warning", !!this.hasContent)
      this.discardButtonTarget.classList.toggle("button--secondary", !this.hasContent)
    }
  }

  async back(event) {
    if (event.defaultPrevented || event.button > 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

    event.preventDefault()
    if (this.leaving) return
    this.leaving = true
    const destination = event.currentTarget.href
    clearTimeout(this.timer)

    if (!await this.flush()) {
      this.leaving = false
      return
    }

    this.skipSaveOnLeave = true
    window.location.assign(destination)
  }

  stopPendingSave() {
    clearTimeout(this.timer)
    this.pending = false
    this.request?.abort()
  }

  async flush() {
    while (this.pending || this.savePromise) {
      if (!await this.save()) return false
    }
    return true
  }

  save(keepalive = false) {
    if (this.savePromise) {
      return this.savePromise.then(saved => saved && (this.pending || this.savePromise) ? this.save(keepalive) : saved)
    }
    this.savePromise = this.performSave(keepalive).finally(() => { this.savePromise = null })
    return this.savePromise
  }

  async performSave(keepalive) {
    clearTimeout(this.timer)
    this.pending = false
    this.request?.abort()
    this.request = keepalive ? null : new AbortController()

    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        body: new FormData(this.element),
        headers: { "Accept": "application/json" },
        keepalive,
        signal: this.request?.signal,
      })
      if (!response.ok) throw new Error()
      const result = await response.json()
      if (result.preview_url) this.previewUrl = result.preview_url
      if (result.save_url) this.urlValue = result.save_url
      if (result.delete_url) this.deleteUrlValue = result.delete_url
      this.persistedValue = true
      this.hasContent = true
      if (this.hasDraftIdTarget) this.draftIdTarget.value = result.draft_id
      if (!keepalive && result.edit_url) window.history.replaceState(window.history.state, "", result.edit_url)
      if (!this.pending) this.statusTarget.textContent = "Entwurf gespeichert"
      this.updateActions()
      return true
    } catch (error) {
      if (error.name !== "AbortError") {
        this.pending = true
        this.statusTarget.textContent = "Entwurf konnte nicht gespeichert werden"
        this.updateActions()
      }
      return false
    }
  }
}
