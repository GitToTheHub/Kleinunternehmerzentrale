import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["number", "format", "start", "abbreviation", "abbreviationField", "status", "collisionHint", "editor", "editorStatus", "preset", "counterYear", "nextCounter", "preview", "editorAbbreviation", "editorAbbreviationField", "globalFormatNotice", "customFormatFlag", "onceHint", "popupFormatFlag", "resetFormat"]
  static values = { url: String }

  connect() {
    this.key = null
    this.autoStart = null
    this.startEdited = false
    this.updateTimer = null
    this.formatHistory = [this.formatTarget.value]
    this.formatHistoryIndex = 0
    this.invalidFormat = event => {
      event.preventDefault()
      this.open()
      this.formatTarget.focus()
      this.showEditorStatus(this.formatTarget.validationMessage)
    }
    this.formatTarget.addEventListener("invalid", this.invalidFormat)
    this.ready = this.update()
  }

  disconnect() {
    clearTimeout(this.updateTimer)
    this.request?.abort()
    this.formatTarget.removeEventListener("invalid", this.invalidFormat)
  }

  open(event) {
    event?.preventDefault()
    this.startedOnBackdrop = false
    if (!this.editorTarget.open) this.editorTarget.showModal()
    this.numberTarget.setAttribute("aria-expanded", "true")
    this.editorTarget.querySelector("h3").focus()
  }

  edit(event) {
    if (event.ctrlKey || event.metaKey || event.altKey) return
    if (event.key.length === 1 || ["Enter", "Backspace", "Delete"].includes(event.key)) this.open(event)
  }

  close(event) {
    event?.preventDefault()
    this.editorTarget.close()
    this.closed()
    this.numberTarget.focus()
  }

  startBackdropClick(event) {
    this.startedOnBackdrop = this.isBackdrop(event)
  }

  closeOnBackdrop(event) {
    const close = this.startedOnBackdrop && this.isBackdrop(event)
    this.startedOnBackdrop = false
    if (close) this.close(event)
  }

  isBackdrop(event) {
    if (event.target !== this.editorTarget) return false
    const rect = this.editorTarget.getBoundingClientRect()
    return event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom
  }

  closed() {
    this.numberTarget.setAttribute("aria-expanded", "false")
  }

  showNumber(value, field = null) {
    this.numberTarget.value = value
    if (this.hasPreviewTarget) this.setStatusContent(this.previewTarget, value, field)
  }

  showStatus(message = "", field = null) {
    this.setStatusContent(this.statusTarget, message, field)
    this.showEditorStatus(message, field)
  }

  showEditorStatus(message = "", field = null) {
    if (this.hasEditorStatusTarget) {
      this.setStatusContent(this.editorStatusTarget, field === "buyer_abbreviation" && this.hasPreviewTarget ? "" : message, field)
    }
  }

  setStatusContent(target, message, field) {
    target.hidden = !message
    if (field !== "buyer_abbreviation" || !message.includes("Kundenkürzel")) {
      target.textContent = message
      return
    }

    const [before, after] = message.split("Kundenkürzel")
    const link = this.element.ownerDocument.createElement("a")
    const inEditor = (this.hasEditorStatusTarget && target === this.editorStatusTarget) || (this.hasPreviewTarget && target === this.previewTarget)
    link.href = inEditor && this.hasEditorAbbreviationTarget ? `#${this.editorAbbreviationTarget.id}` : "#invoice_buyer_abbreviation"
    link.dataset.action = "click->invoice-number#focusAbbreviation"
    link.textContent = "Kundenkürzel"
    target.replaceChildren(
      this.element.ownerDocument.createTextNode(before),
      link,
      this.element.ownerDocument.createTextNode(after)
    )
  }

  focusAbbreviation(event) {
    event.preventDefault()
    const field = this.hasEditorTarget && this.editorTarget.open && this.hasEditorAbbreviationTarget
      ? this.editorAbbreviationTarget : this.abbreviationTarget
    field.focus()
    field.scrollIntoView({ behavior: "smooth", block: "center" })
  }

  editAbbreviation(event) {
    this.abbreviationTarget.value = this.editorAbbreviationTarget.value
    this.abbreviationTarget.dispatchEvent(new Event(event.type, { bubbles: true }))
  }

  updateTemplates(date, format, abbreviation, typeCode = "RE") {
    const [year, month, day] = /^\d{4}-\d{2}-\d{2}$/.test(date) ? date.split("-") : ["JJJJ", "MM", "TT"]
    const values = { "[Rechnungsart]": typeCode, "[Rechnungstyp]": typeCode, "[Jahr]": year, "[Monat]": month, "[Tag]": day, "[Kundenkürzel]": abbreviation.trim().toUpperCase() || "MF", "[Fortlaufendenummer]": "0001", "[Tageszähler]": "01" }
    for (const preset of this.presetTargets || []) {
      preset.setAttribute("aria-pressed", String(preset.dataset.format === format))
      preset.querySelector("[data-format-example]").textContent = preset.dataset.format.replace(/\[[^\]]+\]/g, token => values[token])
    }
  }

  preset(event) {
    if (event.type === "keydown") {
      if (!["Enter", " "].includes(event.key)) return
      event.preventDefault()
      if (event.repeat) return
    }
    const selection = event.currentTarget.ownerDocument?.getSelection?.()
    if (event.type !== "keydown" && event.detail !== 0 && selection && !selection.isCollapsed && selection.containsNode(event.currentTarget, true)) {
      event.preventDefault()
      return
    }
    this.formatTarget.value = event.currentTarget.dataset.format
    this.formatTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  recordFormat(value) {
    if (this.formatHistory[this.formatHistoryIndex] === value) return
    this.formatHistory = this.formatHistory.slice(0, this.formatHistoryIndex + 1)
    this.formatHistory.push(value)
    this.formatHistoryIndex = this.formatHistory.length - 1
  }

  undo(event) {
    const modifier = event.ctrlKey || event.metaKey
    const key = event.key.toLowerCase()
    const undo = modifier && key === "z" && !event.shiftKey
    const redo = modifier && (key === "y" || (key === "z" && event.shiftKey))
    if (!undo && !redo) return
    const nextIndex = this.formatHistoryIndex + (undo ? -1 : 1)
    if (nextIndex < 0 || nextIndex >= this.formatHistory.length) return
    event.preventDefault()
    const cursor = this.formatTarget.selectionStart
    this.formatHistoryIndex = nextIndex
    this.formatTarget.value = this.formatHistory[nextIndex]
    const position = Math.min(cursor, this.formatTarget.value.length)
    this.formatTarget.setSelectionRange(position, position)
    this.formatTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  insertToken(event) {
    const field = this.formatTarget
    const token = event.currentTarget.dataset.token
    const start = field.selectionStart ?? field.value.length
    const end = field.selectionEnd ?? start
    if (field.value.length - (end - start) + token.length > field.maxLength) {
      this.showStatus("Das Format darf höchstens 256 Zeichen enthalten.")
      return
    }
    field.setRangeText(token, start, end, "end")
    field.dispatchEvent(new Event("input", { bubbles: true }))
    field.focus()
  }

  resetFormat(event) {
    event.preventDefault()
    const source = this.hasGlobalFormatNoticeTarget ? this.globalFormatNoticeTarget : this.customFormatFlagTarget
    this.formatTarget.value = source.dataset.globalFormat
    this.formatTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.formatTarget.focus()
  }

  describeFormatChanges(previous, current) {
    const tokens = format => format.match(/\[[^\]]+\]/g) || []
    const before = tokens(previous)
    const after = tokens(current)
    const counts = list => list.reduce((result, token) => ({ ...result, [token]: (result[token] || 0) + 1 }), {})
    const oldCounts = counts(before)
    const newCounts = counts(after)
    const changes = []
    for (const token of new Set([...before, ...after])) {
      const difference = (newCounts[token] || 0) - (oldCounts[token] || 0)
      if (difference) changes.push(`${token.slice(1, -1)}${Math.abs(difference) > 1 ? ` (${Math.abs(difference)}×)` : ""} ${difference > 0 ? "hinzugefügt" : "entfernt"}.`)
    }
    const common = list => {
      const remaining = Object.fromEntries(Object.keys(oldCounts).map(token => [token, Math.min(oldCounts[token], newCounts[token] || 0)]))
      return list.filter(token => remaining[token] > 0 && remaining[token]--).join("|")
    }
    if (common(before) !== common(after)) changes.push("Reihenfolge der Platzhalter geändert.")
    const literal = format => format.replace(/\[[^\]]+\]/g, "")
    const text = format => literal(format).replace(/[\s\-._/]+/g, "")
    if (text(previous) !== text(current)) changes.push("Fester Text geändert.")
    else if (!changes.length && literal(previous) !== literal(current)) changes.push("Trennzeichen geändert.")
    return changes.join(" ")
  }

  updateGlobalFormatNotice() {
    if (this.hasOnceHintTarget) {
      this.onceHintTarget.hidden = !this.element.querySelector('[name="invoice[invoice_number_format_once]"][type="checkbox"]')?.checked
    }
    const notice = this.hasGlobalFormatNoticeTarget ? this.globalFormatNoticeTarget : null
    const flag = this.hasCustomFormatFlagTarget ? this.customFormatFlagTarget : null
    if (!notice && !flag) return
    const globalFormat = notice?.dataset.globalFormat ?? flag.dataset.globalFormat
    const different = this.formatTarget.value !== globalFormat
    if (this.hasResetFormatTarget) this.resetFormatTarget.hidden = !different
    const changes = different ? this.describeFormatChanges(globalFormat, this.formatTarget.value) : ""
    if (notice) {
      notice.textContent = different ? `${notice.dataset.customNotice} ${changes}` : notice.dataset.defaultNotice
      notice.classList.toggle("invoice-status", different)
    }
    const popup = this.hasPopupFormatFlagTarget ? this.popupFormatFlagTarget : null
    const once = this.element.querySelector('[name="invoice[invoice_number_format_once]"][type="checkbox"]')?.checked
    for (const target of [flag, popup].filter(Boolean)) {
      target.hidden = !different
      const scope = target.dataset.globalNotice && !once ? target.dataset.globalNotice : target.dataset.localNotice
      target.textContent = different ? `${scope}. ${changes}` : scope
    }
  }

  async update(event) {
    this.updateGlobalFormatNotice()
    if (this.hasStartTarget && event?.target === this.startTarget && ["input", "change"].includes(event.type)) this.startEdited = true
    if (event?.type === "input" && event.target === this.formatTarget) {
      this.recordFormat(this.formatTarget.value)
      clearTimeout(this.updateTimer)
      this.updateTimer = setTimeout(() => this.update(), 200)
      return
    }
    clearTimeout(this.updateTimer)
    const date = this.element.querySelector("#invoice_issued_on").value
    const format = this.formatTarget.value
    this.recordFormat(format)
    const year = date.split("-")[0]
    if (this.previousCounterYear && this.previousCounterYear !== year && this.hasStartTarget) {
      this.startTarget.value = ""
      this.autoStart = null
      this.startEdited = false
    }
    this.previousCounterYear = year
    if (this.hasCounterYearTarget) this.counterYearTarget.textContent = date.split("-")[0] || "das Rechnungsjahr"
    const hasCounter = format.includes("[Fortlaufendenummer]")
    if (this.hasStartTarget) this.startTarget.disabled = !hasCounter
    const start = this.hasStartTarget && hasCounter && (this.startEdited || this.startTarget.value !== this.autoStart) ? this.startTarget.value : ""
    const abbreviation = this.abbreviationTarget.value
    const selectedType = this.element.querySelector('input[name="invoice[billing_kind]"]:checked, input[name="document_kind"]')
    const billingKind = selectedType?.value || "regular"
    this.updateTemplates(date, format, abbreviation, selectedType?.dataset.numberCode || "RE")
    const needsAbbreviation = format.includes("[Kundenkürzel]")
    this.abbreviationTarget.required = needsAbbreviation
    if (this.hasAbbreviationFieldTarget) this.abbreviationFieldTarget.hidden = !needsAbbreviation
    if (this.hasEditorAbbreviationTarget) {
      this.editorAbbreviationFieldTarget.hidden = !needsAbbreviation
      this.editorAbbreviationTarget.disabled = !needsAbbreviation
      if (this.editorAbbreviationTarget.value !== abbreviation) this.editorAbbreviationTarget.value = abbreviation
    }
    const key = JSON.stringify([date, format, abbreviation, start, billingKind])
    if (key === this.key) return
    if (this.hasNextCounterTarget) this.nextCounterTarget.textContent = hasCounter ? "Nächste fortlaufende Nummer: wird ermittelt …" : ""
    this.key = key
    this.request?.abort()
    if (this.hasStartTarget) this.startTarget.setCustomValidity("")
    this.formatTarget.setCustomValidity("")
    this.abbreviationTarget.setCustomValidity("")
    if (this.hasEditorAbbreviationTarget) this.editorAbbreviationTarget.setCustomValidity("")
    this.showStatus()
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      if (this.hasNextCounterTarget) this.nextCounterTarget.textContent = ""
      this.showNumber("Rechnungsdatum ergänzen")
      return
    }
    const request = this.request = new AbortController()
    const query = new URLSearchParams({ issued_on: date, invoice_number_format: format, buyer_abbreviation: abbreviation, billing_kind: billingKind })
    if (start) query.set("invoice_number_last", start)
    try {
      const separator = this.urlValue.includes("?") ? "&" : "?"
      const response = await fetch(`${this.urlValue}${separator}${query}`, {
        headers: { Accept: "application/json" }, signal: request.signal,
      })
      const result = await response.json()
      if (request.signal.aborted) return
      if (this.hasNextCounterTarget) {
        this.nextCounterTarget.textContent = hasCounter && result.sequence != null ? `Nächste fortlaufende Nummer: ${result.sequence}` : ""
      }
      if (this.hasStartTarget && !start && (!this.startEdited || !hasCounter) && (response.ok || result.sequence != null)) {
        this.autoStart = !hasCounter || result.sequence == null ? "" : String(result.sequence - 1)
        this.startTarget.value = this.autoStart
      }
      if (!response.ok) {
        if (!result.error) throw new Error()
        const field = ["invoice_number_last", "invoice_number_start"].includes(result.field) && this.hasStartTarget ? this.startTarget : result.field === "buyer_abbreviation" ? this.abbreviationTarget : this.formatTarget
        field.setCustomValidity(result.error)
        if (field === this.abbreviationTarget && this.hasEditorAbbreviationTarget) this.editorAbbreviationTarget.setCustomValidity(result.error)
        if (field === this.formatTarget) {
          this.showEditorStatus(result.error)
          return
        }
        this.showStatus(result.error, result.field)
        this.showNumber(result.field === "buyer_abbreviation" ? result.error : "Rechnungsnummernformat prüfen", result.field)
        return
      }
      this.collisionHintTarget.hidden = hasCounter || format.includes("[Tageszähler]")
      this.showNumber(result.invoice_number)
    } catch (error) {
      if (!request.signal.aborted) {
        this.key = null
        if (this.hasNextCounterTarget && hasCounter) this.nextCounterTarget.textContent = "Nächste fortlaufende Nummer: konnte nicht ermittelt werden"
        this.showNumber("Wird beim Erstellen vergeben")
      }
    }
  }
}
