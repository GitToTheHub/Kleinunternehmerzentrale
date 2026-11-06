import { Controller } from "@hotwired/stimulus"

// Action Text/Trix handles editing and selection. Keep descriptions as HTML in the
// existing details field so drafts, immutable invoices and XML exports stay compatible.
export default class extends Controller {
  static targets = ["editor", "linkText"]

  connect() {
    this.initialized = !!this.editorTarget.editor
  }

  ready() { this.initialized = true }

  sync() {
    if (!this.initialized || this.normalizing) return
    this.editorTarget.inputElement.dispatchEvent(new Event("input", { bubbles: true }))
  }

  // Keep the "- " shortcut, using Trix's API before its normal space handling.
  listShortcut(event) {
    if (event.key !== " " || event.isComposing || event.ctrlKey || event.metaKey || event.altKey) return
    const editor = this.editorTarget.editor
    const [start, end] = editor.getSelectedRange()
    if (start !== end || editor.attributeIsActive("bullet")) return
    const text = editor.getDocument().toString()
    const lineStart = text.lastIndexOf("\n", start - 1) + 1
    if (!/^\s*[-–—]$/.test(text.slice(lineStart, start))) return
    event.preventDefault()
    event.stopPropagation()
    this.normalizing = true
    try {
      editor.recordUndoEntry("Liste")
      editor.setSelectedRange([lineStart, start])
      editor.deleteInDirection("backward")
      editor.activateAttribute("bullet")
      editor.setSelectedRange([lineStart, lineStart])
    } finally {
      this.normalizing = false
    }
    this.sync()
  }

  showLink(event) {
    if (event.dialogName !== "href") return
    this.pendingLink = null
    this.linkRange = this.editorTarget.editor.getSelectedRange()
    this.linkTextTarget.value = this.editorTarget.editor.getDocument().getStringAtRange(this.linkRange)
  }

  finishLink(event) {
    if (event.dialogName !== "href" || !this.pendingLink) return
    const { range: originalRange, label, address } = this.pendingLink
    this.pendingLink = null
    const range = originalRange[0] === originalRange[1] ? [originalRange[0], originalRange[0] + address.length] : originalRange
    const editor = this.editorTarget.editor
    if (editor.getDocument().getStringAtRange(range) === label) return
    editor.setSelectedRange(range)
    editor.insertString(label)
    const end = range[0] + label.length
    editor.setSelectedRange([range[0], end])
    editor.activateAttribute("href", address)
    editor.setSelectedRange([end, end])
    editor.deactivateAttribute("href")
  }

  normalizeLink(event) {
    const apply = event.type === "click" && event.target.closest('[data-trix-method="setAttribute"]')
    const enter = event.type === "keydown" && event.key === "Enter" && event.target.matches('[data-trix-input]')
    if (!apply && !enter) return
    if (enter && event.target === this.linkTextTarget) {
      event.preventDefault()
      event.stopPropagation()
      this.element.querySelector('[data-trix-dialog="href"] [data-trix-method="setAttribute"]').click()
      return
    }
    const input = this.element.querySelector('[data-trix-dialog="href"][data-trix-active] input[name="href"]')
    if (!input) return
    const value = input.value.trim()
    input.value = /^(?:[\p{L}\d-]+\.)+[\p{L}\d-]+(?::\d+)?(?:[/?#]\S*)?$/u.test(value) ? `https://${value}` : value
    this.pendingLink = null
    if (!input.checkValidity()) return
    try {
      if (!["http:", "https:", "mailto:", "tel:", "ftp:"].includes(new URL(input.value).protocol)) return
      this.pendingLink = { range: this.linkRange, label: this.linkTextTarget.value.trim() || input.value, address: input.value }
    } catch { /* Trix reports invalid addresses without changing the selected text. */ }
  }

  clearLinkError(event) {
    event.target.setCustomValidity("")
    event.target.removeAttribute("data-trix-validate")
    event.target.classList.remove("trix-validate")
  }

  blockFiles(event) { event.preventDefault() }

  blockAttachment(event) {
    event.preventDefault()
    event.stopPropagation()
    event.attachment.remove()
  }

  // Accept only clipboard text, including when copied from another rich-text editor.
  paste(event) {
    event.preventDefault()
    event.stopPropagation()
    this.editorTarget.editor.insertString(event.clipboardData.getData("text/plain"))
  }

  clear() {
    this.editorTarget.editor.loadHTML("")
  }
}
