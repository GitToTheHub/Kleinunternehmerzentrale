import { Controller } from "@hotwired/stimulus"

// Kleiner Texteditor für die Positionsbeschreibung: fett, kursiv, Aufzählung.
// Der HTML-Inhalt wird in ein verstecktes Feld geschrieben, der Server bereinigt ihn erneut.
export default class extends Controller {
  static targets = ["editor", "input", "button"]

  connect() {
    this.editorTarget.innerHTML = this.inputTarget.value
    document.execCommand("defaultParagraphSeparator", false, "p")
  }

  format(event) {
    event.preventDefault()
    this.editorTarget.focus()
    document.execCommand(event.currentTarget.dataset.command)
    this.sync()
  }

  keepSelection(event) {
    event.preventDefault()
  }

  // Beim Einfügen nur Text übernehmen, damit keine fremde Formatierung hineinkommt.
  paste(event) {
    event.preventDefault()
    document.execCommand("insertText", false, event.clipboardData.getData("text/plain"))
  }

  sync() {
    const empty = this.editorTarget.textContent.trim() === "" && !this.editorTarget.querySelector("li")
    this.inputTarget.value = empty ? "" : this.editorTarget.innerHTML
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.buttonTargets.forEach((b) => b.classList.toggle("is-active", document.queryCommandState(b.dataset.command)))
  }

  clear() {
    this.editorTarget.innerHTML = ""
    this.sync()
  }
}
