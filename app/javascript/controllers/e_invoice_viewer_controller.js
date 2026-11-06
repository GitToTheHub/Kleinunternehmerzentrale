import { Controller } from "@hotwired/stimulus"
import { decodeInvoiceXml, parseInvoiceXml, formatInvoiceDate, formatInvoiceNumber, formatInvoiceMoney } from "e_invoice"

const MAX_FILE_BYTES = 20 * 1024 * 1024
const MAX_XML_BYTES = 5 * 1024 * 1024
const UNITS = { C62: "Stück", HUR: "Stunden", DAY: "Tage", MON: "Monate", KGM: "kg", MTR: "m", MTK: "m²", MTQ: "m³", LTR: "Liter", LS: "Pauschale" }
const PAYMENT_TYPES = { "10": "Barzahlung", "30": "Überweisung", "48": "Kartenzahlung", "49": "Lastschrift", "58": "SEPA-Überweisung", "59": "SEPA-Lastschrift" }

function element(tag, text, className) {
  const node = document.createElement(tag)
  if (text !== undefined) node.textContent = text
  if (className) node.className = className
  return node
}

function detailsList(entries) {
  const list = element("dl", undefined, "e-invoice-viewer__details")
  for (const [label, text] of entries) {
    if (text === "" || text === undefined) continue
    const row = element("div")
    row.append(element("dt", label), element("dd", text))
    list.append(row)
  }
  return list
}

export default class extends Controller {
  static targets = ["file", "status", "error", "reset", "print", "result"]
  static values = { workerUrl: String }

  connect() {
    this.version = 0
    this.tasks = new Set()
  }

  disconnect() { this.clear() }

  clear(clearFile = true) {
    this.version++
    for (const task of this.tasks) task.destroy().catch(() => {})
    this.tasks.clear()
    if (clearFile) this.fileTarget.value = ""
    this.statusTarget.textContent = ""
    this.errorTarget.hidden = true
    this.errorTarget.textContent = ""
    this.resetTarget.hidden = true
    this.printTarget.hidden = true
    this.resultTarget.hidden = true
    this.resultTarget.replaceChildren()
    this.resultTarget.setAttribute("aria-busy", "false")
  }

  async open() {
    const file = this.fileTarget.files[0]
    if (!file) return
    this.clear(false)
    const version = this.version
    this.statusTarget.textContent = "Rechnungsdatei wird gelesen …"
    this.resultTarget.setAttribute("aria-busy", "true")
    this.resetTarget.hidden = false
    try {
      if (file.size > MAX_FILE_BYTES) throw new Error("Die Datei ist zu groß. Bitte wähle eine Datei mit höchstens 20 MB.")
      const bytes = new Uint8Array(await file.arrayBuffer())
      if (version !== this.version) return
      const pdf = new TextDecoder().decode(bytes.slice(0, 5)) === "%PDF-"
      const invoice = pdf ? await this.readPdf(bytes) : this.readXml(bytes)
      if (version !== this.version) return
      this.render(invoice, file.name, pdf)
      this.statusTarget.textContent = `„${file.name}“ wurde geöffnet.`
      this.printTarget.hidden = false
      this.resultTarget.hidden = false
    } catch (error) {
      if (version !== this.version) return
      this.statusTarget.textContent = ""
      this.errorTarget.textContent = error.name === "PasswordException" ? "Die PDF-Datei ist passwortgeschützt. Bitte öffne eine ungeschützte Rechnungsdatei." :
        error.name === "InvalidPDFException" ? "Die PDF-Datei ist beschädigt oder konnte nicht gelesen werden." :
        error.name === "Error" ? error.message : "Die Datei konnte nicht gelesen werden. Bitte wähle eine XML-Rechnung oder eine ZUGFeRD-PDF."
      this.errorTarget.hidden = false
    } finally {
      if (version === this.version) this.resultTarget.setAttribute("aria-busy", "false")
    }
  }

  readXml(bytes) {
    if (bytes.length > MAX_XML_BYTES) throw new Error("Die XML-Rechnungsdaten sind zu groß. Unterstützt werden bis zu 5 MB XML-Daten.")
    return parseInvoiceXml(decodeInvoiceXml(bytes))
  }

  async readPdf(bytes) {
    const { getDocument, GlobalWorkerOptions } = await import("pdfjs")
    GlobalWorkerOptions.workerSrc = this.workerUrlValue
    const task = getDocument({ data: bytes, isEvalSupported: false, useWorkerFetch: false, disableFontFace: true, verbosity: 0 })
    this.tasks.add(task)
    try {
      const pdf = await task.promise
      const attachments = await pdf.getAttachments()
      const invoices = []
      let xmlError
      for (const [id, attachment] of attachments || []) {
        if (!/\.xml$/i.test(attachment.filename)) continue
        const content = await pdf.getAttachmentContent(id)
        if (!content) continue
        try { invoices.push(this.readXml(content)) }
        catch (error) { xmlError = error }
      }
      if (!invoices.length) throw xmlError || new Error("In dieser PDF-Datei wurde keine eingebettete E-Rechnung gefunden. Bitte wähle eine ZUGFeRD-PDF oder die originale XML-Datei.")
      if (invoices.length > 1) throw new Error("Diese PDF enthält mehrere XML-Rechnungen. Bitte öffne die gewünschte XML-Datei einzeln.")
      return invoices[0]
    } finally {
      await task.destroy()
      this.tasks.delete(task)
    }
  }

  render(invoice, filename, pdf) {
    const result = this.resultTarget
    const money = value => formatInvoiceMoney(value, invoice.currency)
    result.replaceChildren(element("h2", `${invoice.type} ${invoice.number}`))
    result.append(element("p", `${filename} · ${pdf ? "ZUGFeRD / Factur-X · " : ""}${invoice.format}`, "e-invoice-viewer__filename"))
    result.append(detailsList([
      ["Rechnungsdatum", formatInvoiceDate(invoice.issued)], ["Zahlbar bis", formatInvoiceDate(invoice.due)],
      ["Leistungsdatum", formatInvoiceDate(invoice.service)], ["Leistung von", formatInvoiceDate(invoice.start)],
      ["Leistung bis", formatInvoiceDate(invoice.end)], ["Währung", invoice.currency], ...invoice.references,
    ]))
    const parties = element("div", undefined, "e-invoice-viewer__parties")
    for (const [title, party] of [["Rechnung von", invoice.seller], ["Rechnung an", invoice.buyer]]) {
      const section = element("section")
      section.append(element("h3", title), element("p", [party.name, ...party.address].join("\n"), "e-invoice-viewer__address"))
      section.append(detailsList([["Ansprechperson", party.contact], ["E-Mail / elektronische Adresse", party.email], ["Telefon", party.phone],
        ...party.identifiers.map(identifier => ["Steuerliche Kennung", identifier])]))
      parties.append(section)
    }
    result.append(parties, element("h3", "Positionen"))
    if (invoice.lines.length) {
      const scroll = element("div", undefined, "e-invoice-viewer__table")
      scroll.tabIndex = 0
      scroll.setAttribute("role", "region")
      scroll.setAttribute("aria-label", "Rechnungspositionen")
      const table = element("table")
      const head = element("thead")
      const headers = element("tr")
      for (const title of ["Leistung oder Artikel", "Menge", "Einzelpreis netto", "USt.", "Betrag netto"]) {
        const th = element("th", title)
        th.scope = "col"
        headers.append(th)
      }
      head.append(headers)
      const body = element("tbody")
      for (const line of invoice.lines) {
        const row = element("tr")
        const description = element("td")
        description.append(element("strong", line.name || `Position ${line.id}`))
        if (line.description) description.append(element("p", line.description))
        for (const adjustment of line.adjustments) description.append(element("p", `${adjustment.label}: ${money(adjustment.amount)} ${adjustment.reason}`))
        const price = line.base && line.base !== "1" ? `${money(line.price)} / ${formatInvoiceNumber(line.base)} ${UNITS[line.unit] || line.unit}` : money(line.price)
        row.append(description, element("td", `${formatInvoiceNumber(line.quantity)} ${UNITS[line.unit] || line.unit}`),
          element("td", price), element("td", line.tax === "" ? "—" : `${formatInvoiceNumber(line.tax)} %`), element("td", money(line.net)))
        body.append(row)
      }
      table.append(head, body)
      scroll.append(table)
      result.append(scroll)
    } else result.append(element("p", "Die Datei enthält keine einzelnen Rechnungspositionen."))

    if (invoice.adjustments.length) {
      result.append(element("h3", "Nachlässe und Zuschläge"))
      for (const adjustment of invoice.adjustments) result.append(element("p", `${adjustment.label}: ${money(adjustment.amount)} ${adjustment.reason}`))
    }
    const totals = detailsList(invoice.totals.filter(([, value]) => value !== "").map(([label, value]) => [label, money(value)]))
    totals.classList.add("e-invoice-viewer__totals")
    result.append(totals)
    if (invoice.taxes.length) {
      result.append(element("h3", "Steuern"))
      for (const tax of invoice.taxes) {
        result.append(element("p", [tax.rate === "" ? `Steuerkategorie ${tax.category}` : `${formatInvoiceNumber(tax.rate)} %`,
          tax.basis ? `auf ${money(tax.basis)}` : "", tax.amount ? `= ${money(tax.amount)}` : "", tax.reason].filter(Boolean).join(" ")))
      }
    }
    if (invoice.payments.length || invoice.terms.length) {
      result.append(element("h3", "Zahlung"))
      for (const payment of invoice.payments) result.append(detailsList([
        ["Zahlungsart", PAYMENT_TYPES[payment.code] || payment.code], ["Konto / IBAN", payment.account], ["Kontoinhaber", payment.holder],
        ["BIC", payment.bic], ["Verwendungszweck", payment.reference], ["Zahlungshinweis", payment.note],
      ]))
      for (const term of invoice.terms) result.append(element("p", term))
    }
    if (invoice.notes.length) {
      result.append(element("h3", "Hinweise zur Rechnung"))
      for (const note of invoice.notes) result.append(element("p", note))
    }
    const allFields = element("details", undefined, "no-print e-invoice-viewer__raw")
    allFields.append(element("summary", "Weitere Angaben aus der XML-Datei"), detailsList(invoice.fields))
    result.append(allFields)
  }

  print() { window.print() }
}
