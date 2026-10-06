import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "template", "row", "title", "remove", "total", "net", "gross", "taxRow"]

  initialize() {
    this.index = 0
  }

  connect() {
    this.index = this.rowTargets.length
    this.renumber()
    this.rowTargets.forEach((row) => this.updateSummary({ currentTarget: row }))
    const first = this.rowTargets.find((row) => this.field(row, "description").value.trim() === "") || this.rowTargets[0]
    if (first) first.open = true
    // Pflichtfeld in einer zugeklappten Position: aufklappen, damit die Meldung sichtbar ist.
    this.element.closest("form").addEventListener("invalid", (event) => {
      const row = event.target.closest("[data-invoice-lines-target='row']")
      if (row && !row.open) this.open(row, { animate: false })
    }, true)
  }

  // Klick auf die Kopfzeile: eigene Animation statt des Standardverhaltens von <details>.
  toggle(event) {
    event.preventDefault()
    const row = event.currentTarget.closest("details")
    if (row.open) {
      this.close(row)
    } else {
      this.open(row)
    }
  }

  // Es ist immer nur eine Position offen, die anderen erscheinen wie auf der Rechnung.
  open(row, { animate = true } = {}) {
    this.rowTargets.filter((other) => other !== row && other.open).forEach((other) => this.close(other, { animate }))
    this.animate(row, true, animate)
  }

  close(row, { animate = true } = {}) {
    this.animate(row, false, animate)
  }

  animate(row, opening, animate) {
    const content = row.querySelector(".invoice-line__content")
    row.animation?.cancel()
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches

    if (opening) row.open = true
    if (!animate || reduce) {
      row.open = opening
      return
    }

    const height = content.getBoundingClientRect().height
    const keyframes = opening ? [{ height: "0px", opacity: 0 }, { height: `${content.scrollHeight}px`, opacity: 1 }]
      : [{ height: `${height}px`, opacity: 1 }, { height: "0px", opacity: 0 }]
    row.animation = content.animate(keyframes, { duration: 250, easing: "ease-out" })
    row.animation.onfinish = () => {
      row.open = opening
      row.animation = null
    }
    row.animation.oncancel = () => { row.animation = null }
  }

  field(row, name) {
    return row.querySelector(`[name$='[${name}]']`)
  }

  updateSummary(event) {
    const row = (event.currentTarget || event.target).closest("[data-invoice-lines-target='row']")
    const unit = this.field(row, "unit_code")
    const quantity = parseFloat(this.field(row, "quantity").value.replace(",", ".")) || 0
    const price = parseFloat(this.field(row, "unit_price").value) || 0
    const money = (n) => n.toLocaleString("de-DE", { style: "currency", currency: "EUR" })
    const number = (n) => n.toLocaleString("de-DE", { maximumFractionDigits: 3 })
    const description = this.field(row, "description").value.trim()

    row.querySelector("[data-summary='description']").textContent = description || "Noch keine Leistung eingetragen"
    row.querySelector("[data-summary='details']").textContent = this.plainText(this.field(row, "details").value)
    row.querySelector("[data-summary='total']").textContent = money(quantity * price)
    row.querySelector("[data-summary='calc']").textContent =
      `${number(quantity)} ${this.unitLabel(unit, quantity)} × ${money(price)} = ${money(quantity * price)}`
    this.updateTotal()
  }

  // Die Beschreibung ist HTML; die Zusammenfassung zeigt nur den Text in einer Zeile.
  plainText(html) {
    const box = document.createElement("div")
    box.innerHTML = html.replace(/<\/?(p|li|ul|ol|div)>|<br\s*\/?>/gi, " ")
    return box.textContent.replace(/\s+/g, " ").trim()
  }

  // Mehrzahl wie auf der Rechnung: 1 Stunde, 3 Stunden.
  unitLabel(unit, quantity) {
    const plurals = { HUR: "Stunden", DAY: "Tage", MON: "Monate" }
    return quantity !== 1 && plurals[unit.value] ? plurals[unit.value] : unit.selectedOptions[0]?.text || ""
  }

  updateTotal() {
    const money = (n) => n.toLocaleString("de-DE", { style: "currency", currency: "EUR" })
    const standard = this.element.closest("form").dataset.taxMode === "standard"
    const netByRate = {}
    let net = 0
    this.rowTargets.forEach((row) => {
      const quantity = parseFloat(this.field(row, "quantity").value.replace(",", ".")) || 0
      const amount = quantity * (parseFloat(this.field(row, "unit_price").value) || 0)
      const rate = this.field(row, "tax_rate").value
      netByRate[rate] = (netByRate[rate] || 0) + amount
      net += amount
    })
    this.totalTarget.textContent = money(net)
    this.netTarget.textContent = money(net)

    // Wie auf der Rechnung: Steuer je Satz aus der Summe aller Positionen, auf Cent gerundet.
    let tax = 0
    this.taxRowTargets.forEach((row) => {
      const rateTax = Math.round((netByRate[row.dataset.rate] || 0) * Number(row.dataset.rate)) / 100
      row.hidden = !standard || !(row.dataset.rate in netByRate)
      row.querySelector("dd").textContent = money(rateTax)
      if (!row.hidden) tax += rateTax
    })
    this.grossTarget.textContent = money(net + tax)
  }

  add() {
    const index = this.index++
    const previous = this.rowTargets[this.rowTargets.length - 1]
    this.listTarget.insertAdjacentHTML("beforeend", this.templateTarget.innerHTML.replaceAll("NEW_RECORD", index))
    const row = this.listTarget.lastElementChild
    this.copyUnit(previous, row)
    this.renumber()
    this.updateSummary({ currentTarget: row })
    this.open(row)
    this.field(row, "description").focus({ preventScroll: true })
  }

  // Neue Position übernimmt die Einheit der vorherigen; bei Stunden folgt der Stundensatz, die Menge nie.
  copyUnit(previous, row) {
    if (!previous) return

    const unit = row.querySelector("select[name$='[unit_code]']")
    unit.value = this.field(previous, "unit_code").value
    this.field(row, "tax_rate").value = this.field(previous, "tax_rate").value
    if (unit.value !== "HUR") return

    // Der Controller der neuen Zeile ist noch nicht verbunden, daher wird der Preis hier direkt gesetzt.
    const rate = this.rowTargets.filter((r) => r !== row && this.field(r, "unit_code").value === "HUR")
      .map((r) => this.field(r, "unit_price").value).filter((v) => parseFloat(v) > 0).pop()
    this.field(row, "unit_price").value = rate || this.element.closest("form").dataset.hourlyRate || 0
  }

  remove(event) {
    // Der Button liegt in der Kopfzeile und darf diese nicht auf- oder zuklappen.
    event.preventDefault()
    event.stopPropagation()
    const row = event.currentTarget.closest("[data-invoice-lines-target='row']")
    if (this.rowTargets.length <= 1) return this.reset(row)

    const wasOpen = row.open
    row.remove()
    this.renumber()
    this.updateTotal()
    if (wasOpen && this.rowTargets.length) this.open(this.rowTargets[this.rowTargets.length - 1])
  }

  // Die einzige Position kann nicht gelöscht werden und wird stattdessen auf den Ausgangszustand gesetzt.
  reset(row) {
    const values = { description: "", details: "", quantity: "1", unit_code: "C62", unit_price: "0", tax_rate: "19" }
    Object.entries(values).forEach(([name, value]) => { this.field(row, name).value = value })
    row.querySelector("[data-controller~='rich-text']")?.dispatchEvent(new CustomEvent("rich-text:clear"))
    this.field(row, "unit_code").dispatchEvent(new Event("change", { bubbles: true }))
    this.field(row, "description").focus({ preventScroll: true })
    if (!row.open) this.open(row)
  }

  // Zeigt "Position 2 von 3" über jeder Leistung.
  renumber() {
    const rows = this.listTarget.querySelectorAll("[data-invoice-lines-target='row']")
    this.removeTargets.forEach((button) => {
      const label = rows.length <= 1 ? "Position leeren" : "Position löschen"
      button.title = label
      button.setAttribute("aria-label", label)
    })
    rows.forEach((row, i) => {
      row.querySelector("[data-invoice-lines-target='title']").textContent = `Position ${i + 1} von ${rows.length}`
    })
  }
}
