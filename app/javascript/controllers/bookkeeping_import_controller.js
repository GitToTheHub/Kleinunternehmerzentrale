import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["mode", "csv", "manual", "year", "position", "caption", "row", "file", "fileLabel", "csvHelp", "pdfHelp", "template", "cutoff", "source", "sum", "amount", "totals", "sumError", "sourceNote"]

  connect() { this.update() }

  updateReferences() {
    const year = this.yearTarget.value
    this.sourceNoteTargets.forEach(element => { element.textContent = JSON.parse(element.dataset.notes)[year] || `Für ${year} sind keine geprüften Formulardaten hinterlegt.` })
    this.positionTargets.forEach(element => { element.textContent = JSON.parse(element.dataset.references)[year] || "Keine Zeilenzuordnung für dieses Jahr" })
    this.rowTargets.forEach(row => {
      const available = row.dataset.years.split(" ").includes(year)
      row.hidden = !available
      row.querySelectorAll("input").forEach(input => { input.disabled = !available || this.modeTarget.value !== "manual" })
    })
    this.captionTargets.forEach(element => { element.textContent = JSON.parse(element.dataset.captions)[year] || "" })
    this.updateTotals()
  }

  parseCents(value) {
    let text = String(value).trim().replace(/€$/, "").trim()
    if (!text) return 0
    if (text.includes(",")) {
      if (!/^-?(?:\d+|\d{1,3}(?:\.\d{3})+),\d{1,2}$/.test(text)) return null
      text = text.replaceAll(".", "").replace(",", ".")
    }
    if (!/^-?\d+(?:\.\d{1,2})?$/.test(text)) return null
    const sign = text.startsWith("-") ? -1 : 1
    const [whole, fraction = ""] = text.replace(/^-/, "").split(".")
    const cents = sign * (Number(whole) * 100 + Number(fraction.padEnd(2, "0")))
    return Number.isSafeInteger(cents) && Math.abs(cents) < 1000000000000 ? cents : null
  }

  updateTotals() {
    const effects = { income: 0, expense: 0, expense_reduction: 0, profit_plus: 0, profit_minus: 0 }
    const sums = { deposits: 0, withdrawals: 0, reserveCreate: 0, reserveRelease: 0 }
    let invalid = false
    for (const input of this.amountTargets) {
      if (input.disabled) continue
      const amount = this.parseCents(input.value)
      if (amount === null) { invalid = true; continue }
      const { effect, key, section } = input.dataset
      if (Object.hasOwn(effects, effect)) effects[effect] += amount
      if (["deposits", "withdrawals"].includes(key)) sums[key] += amount
      if (section === "27" && effect === "expense") sums.reserveCreate += amount
      if (section === "27" && effect === "income") sums.reserveRelease += amount
    }
    sums.income = effects.income
    sums.expenses = effects.expense - effects.expense_reduction
    sums.corrections = effects.profit_plus - effects.profit_minus
    sums.surplus = sums.income - sums.expenses + sums.corrections
    const formatter = new Intl.NumberFormat("de-DE", { style: "currency", currency: "EUR" })
    this.sumTargets.forEach(output => { output.textContent = invalid ? "–" : formatter.format(sums[output.dataset.key] / 100) })
    this.sumErrorTarget.hidden = !invalid
    this.totalsTarget.hidden = this.modeTarget.value !== "manual"
  }

  update() {
    const mode = this.modeTarget.value
    if (this.previousMode && this.previousMode !== mode) this.fileTarget.value = ""
    this.previousMode = mode
    const upload = mode !== "manual"
    const pdf = mode === "pdf"
    this.csvTarget.hidden = !upload
    this.manualTarget.hidden = upload
    this.fileTarget.disabled = !upload
    this.fileTarget.required = upload
    this.fileTarget.accept = pdf ? ".pdf,application/pdf" : ".csv,text/csv"
    this.fileLabelTarget.textContent = pdf ? "sevdesk-EÜR als PDF" : "CSV-Datei mit EÜR-Summen"
    this.csvHelpTarget.hidden = pdf
    this.pdfHelpTarget.hidden = !pdf
    this.templateTarget.hidden = pdf
    this.yearTarget.disabled = pdf
    this.sourceTarget.required = !pdf
    this.cutoffTarget.required = !pdf
    const display = document.getElementById(`${this.cutoffTarget.id}_display`)
    if (display) display.required = !pdf
    this.updateReferences()
  }
}
