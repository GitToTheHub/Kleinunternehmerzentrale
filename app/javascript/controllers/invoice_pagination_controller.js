import { Controller } from "@hotwired/stimulus"

const PAGE_STYLES = `
  @page { size: A4; margin: 20mm 20mm 20mm 25mm; }
  .pagedjs_page_content .print-invoice { width: auto; min-height: 0; margin: 0; padding: 0; outline: 0; }
  .print-invoice__header, .invoice-payment, .invoice-position-row, .invoice-table thead, .invoice-table tfoot tr, .invoice-table tbody[data-invoice-totals] tr { break-inside: avoid; }
  .invoice-table tfoot { display: table-row-group; }
`

export default class extends Controller {
  static targets = ["source", "pages", "status"]

  connect() {
    this.cancelled = false
    if (document.body.classList.contains("invoice-preview-embedded")) {
      this.resizeObserver = new ResizeObserver(() => this.fitPreview())
      this.resizeObserver.observe(this.element)
    }
    this.ready = this.paginate()
  }

  disconnect() { this.teardown() }

  teardown() {
    this.cancelled = true
    this.resizeObserver?.disconnect()
    if (this.previewer?.chunker?.pagesArea) this.previewer.chunker.destroy()
    this.previewer?.polisher?.destroy()
    this.previewer = null
    this.sourceTarget.hidden = false
    this.pagesTarget.replaceChildren()
    this.pagesTarget.classList.add("invoice-pages--rendering")
  }

  fitPreview() {
    if (!this.resizeObserver) return
    const page = this.pagesTarget.querySelector(".pagedjs_page")
    if (page) this.pagesTarget.style.zoom = Math.min(1, this.element.clientWidth / page.offsetWidth)
  }

  repeatTableHeader(rendered, original) {
    const element = rendered.nodeType === 1 ? rendered : rendered.parentElement
    const table = element?.closest(".invoice-table[data-split-from]")
    if (!table || table.querySelector("thead")) return

    const sourceElement = original.nodeType === 1 ? original : original.parentElement
    if (!sourceElement?.closest(".invoice-position-row, .invoice-description-row")) return

    const header = sourceElement?.closest(".invoice-table")?.querySelector("thead")
    if (header) {
      const repeated = header.cloneNode(true)
      repeated.dataset.invoiceRepeatedHeader = "true"
      table.insertBefore(repeated, table.querySelector("tbody, tfoot"))
    }
  }

  removeOrphanedHeaders(page) {
    page.querySelectorAll("thead[data-invoice-repeated-header]").forEach((header) => {
      const table = header.closest(".invoice-table")
      const hasPositions = [...table.querySelectorAll(".invoice-position-row, .invoice-description-row")]
        .some((row) => row.textContent.trim())
      if (!hasPositions) header.remove()
    })
  }

  async paginate() {
    try {
      const { Previewer } = await import("pagedjs")
      await document.fonts.ready
      if (this.cancelled) return false

      this.previewer = new Previewer()
      // Insert the repeated header during layout so its height is included in the page break.
      this.previewer.chunker.hooks.renderNode.register((rendered, original) => {
        this.repeatTableHeader(rendered, original)
      })
      this.previewer.chunker.hooks.afterPageLayout.register((page) => {
        this.removeOrphanedHeaders(page)
      })
      const content = document.createDocumentFragment()
      const source = this.sourceTarget.cloneNode(true)
      source.removeAttribute("data-invoice-pagination-target")
      // Paged.js treats native table footers as repeating content and can drop them at a page boundary.
      // Lay totals out as ordinary rows, then restore their table-footer semantics after pagination.
      source.querySelectorAll("tfoot").forEach((footer) => {
        const body = document.createElement("tbody")
        body.dataset.invoiceTotals = "true"
        body.append(...footer.childNodes)
        footer.replaceWith(body)
      })
      content.append(source)
      await this.previewer.preview(content, [{ [window.location.href]: PAGE_STYLES }], this.pagesTarget)
      if (this.cancelled) return false

      const pages = this.pagesTarget.querySelectorAll(".pagedjs_page")
      if (!pages.length) throw new Error("No invoice pages rendered")
      this.pagesTarget.querySelectorAll("tbody[data-invoice-totals]").forEach((body) => {
        const footer = document.createElement("tfoot")
        footer.append(...body.childNodes)
        body.replaceWith(footer)
      })
      pages.forEach((page, index) => {
        const footer = document.createElement("div")
        footer.className = "invoice-page-number"
        footer.textContent = `Seite ${index + 1} von ${pages.length}`
        page.append(footer)
      })

      this.sourceTarget.hidden = true
      this.pagesTarget.classList.remove("invoice-pages--rendering")
      this.statusTarget.hidden = true
      this.fitPreview()
      return true
    } catch (error) {
      if (!this.cancelled) {
        this.teardown()
        this.statusTarget.textContent = "Die Seitenvorschau konnte nicht vorbereitet werden. Bitte lade die Seite erneut."
      }
      return false
    }
  }
}
