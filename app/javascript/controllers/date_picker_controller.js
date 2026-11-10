import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "calendar", "month", "days", "todayButton"]
  static values = { minDateField: String, minError: String, minExclusive: Boolean }

  connect() {
    this.inDialog = Boolean(this.element.closest("dialog"))
    if (this.inDialog) this.calendarTarget.setAttribute("popover", "manual")
    // Keep pointer clicks from blurring the field before the calendar button's
    // click runs (some browsers report no relatedTarget for button focus).
    this.keepCalendarFocus = event => {
      if (event.button === 0 && event.target.closest("button")) event.preventDefault()
    }
    this.calendarTarget.addEventListener("pointerdown", this.keepCalendarFocus)
    this.textInput = document.createElement("input")
    this.textInput.type = "text"
    this.textInput.id = `${this.inputTarget.id}_display`
    this.textInput.placeholder = "TT.MM.JJJJ"
    this.textInput.autocomplete = "off"
    if (this.inputTarget.dataset.action) this.textInput.dataset.action = this.inputTarget.dataset.action
    this.textInput.setAttribute("aria-haspopup", "dialog")
    this.textInput.setAttribute("aria-controls", this.calendarTarget.id)
    this.textInput.setAttribute("aria-expanded", "false")
    this.textInput.addEventListener("click", event => this.open(event))
    this.textInput.addEventListener("blur", () => {
      if (this.inputTarget.value) this.syncDisplay()
    })
    this.inputTarget.after(this.textInput)
    this.label = document.querySelector(`label[for="${this.inputTarget.id}"]`)
    if (this.label) this.label.htmlFor = this.textInput.id
    this.inputTarget.type = "hidden"
    this.syncDisplay()
    this.syncConstraints()
    this.syncMinimum()
    this.observer = new MutationObserver(() => this.syncConstraints())
    this.observer.observe(this.inputTarget, { attributes: true, attributeFilter: ["required", "disabled", "readonly", "min", "max"] })
    this.element.classList.add("date-picker--enhanced")
    this.reposition = () => this.position(true)
    window.visualViewport?.addEventListener("resize", this.reposition)
    window.visualViewport?.addEventListener("scroll", this.reposition)
  }

  disconnect() {
    window.visualViewport?.removeEventListener("resize", this.reposition)
    window.visualViewport?.removeEventListener("scroll", this.reposition)
    this.observer?.disconnect()
    this.calendarTarget.removeEventListener("pointerdown", this.keepCalendarFocus)
    this.textInput?.remove()
    this.inputTarget.type = "date"
    if (this.label) this.label.htmlFor = this.inputTarget.id
    this.element.classList.remove("date-picker--enhanced")
    this.close()
  }

  syncConstraints() {
    this.textInput.required = this.inputTarget.required
    this.textInput.disabled = this.inputTarget.disabled
    this.textInput.readOnly = this.inputTarget.readOnly
    this.validateText()
  }

  syncDisplay() {
    this.textInput.value = this.inputTarget.value ? this.inputTarget.value.split("-").reverse().join(".") : ""
    this.validateText()
  }

  parse(value, today = new Date()) {
    const match = value.trim().match(/^(\d{1,2})\.(\d{1,2})(?:\.(\d{4})|\.?)$/)
    if (!match) return ""
    const day = Number(match[1])
    const month = Number(match[2])
    let year = match[3] ? Number(match[3]) : today.getFullYear()
    if (!match[3]) {
      if (today.getMonth() === 11 && month === 1) year += 1
      else if (today.getMonth() === 0 && month === 12) year -= 1
    }
    const date = new Date(year, month - 1, day)
    if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) return ""
    return this.iso(date)
  }

  syncMinimum() {
    if (!this.minDateFieldValue) return
    const source = document.getElementById(this.minDateFieldValue)
    if (!source) return
    let minimum = source.value
    if (minimum && this.minExclusiveValue) {
      const date = new Date(`${minimum}T12:00:00`)
      date.setDate(date.getDate() + 1)
      minimum = this.iso(date)
    }
    const changed = this.inputTarget.min !== minimum
    this.inputTarget.min = minimum
    this.validateText()
    if (changed && !this.calendarTarget.hidden) this.render()
  }

  validateText() {
    const value = this.parse(this.textInput.value)
    let message = ""
    if (this.textInput.value.trim()) {
      if (!value || (this.inputTarget.max && value > this.inputTarget.max)) message = "Bitte gib ein gültiges Datum als TT.MM.JJJJ ein."
      else if (this.inputTarget.min && value < this.inputTarget.min) message = this.minErrorValue || "Bitte gib ein gültiges Datum als TT.MM.JJJJ ein."
    }
    this.textInput.setCustomValidity(message)
  }

  update(event) {
    if (event.target === this.textInput) {
      this.inputTarget.value = this.parse(this.textInput.value)
      this.validateText()
      if (event.type === "input") {
        if (this.calendarTarget.hidden || this.inputTarget.value) this.open(event)
        else this.render()
      }
    } else if (event.target === this.inputTarget) this.syncDisplay()
  }

  open(event) {
    if (this.inputTarget.disabled || this.inputTarget.readOnly) return
    this.dispatch("opening", { prefix: "date-picker" })
    this.syncMinimum()
    let date = this.inputTarget.value ? new Date(`${this.inputTarget.value}T12:00:00`) : new Date()
    if (!this.inputTarget.value && this.minExclusiveValue && this.inputTarget.min) date = new Date(`${this.inputTarget.min}T12:00:00`)
    if (this.inputTarget.min && this.iso(date) < this.inputTarget.min) date = new Date(`${this.inputTarget.min}T12:00:00`)
    if (this.inputTarget.max && this.iso(date) > this.inputTarget.max) date = new Date(`${this.inputTarget.max}T12:00:00`)
    this.focusDate = this.iso(date)
    this.visibleMonth = new Date(date.getFullYear(), date.getMonth(), 1)
    this.calendarTarget.hidden = false
    if (this.inDialog) this.calendarTarget.showPopover()
    this.textInput.setAttribute("aria-expanded", "true")
    this.render()
    this.position(true)
  }

  position(ensureVisible = false) {
    if (this.calendarTarget.hidden) return
    const margin = 8
    const viewport = window.visualViewport
    const viewportTop = viewport?.offsetTop || 0
    const viewportLeft = viewport?.offsetLeft || 0
    const viewportRight = viewportLeft + (viewport?.width || window.innerWidth)
    const viewportBottom = viewportTop + (viewport?.height || window.innerHeight)
    let field = this.textInput.getBoundingClientRect()
    const actions = this.inDialog
      ? this.element.closest("dialog").querySelector(".invoice-actions")
      : document.querySelector(".invoice-form__actions")
    const footer = actions?.getBoundingClientRect()
    const bottom = footer && footer.bottom > viewportTop && footer.top < viewportBottom
      ? Math.min(viewportBottom, footer.top) - margin : viewportBottom - margin
    const top = viewportTop + margin
    const calendar = this.calendarTarget.getBoundingClientRect()
    if (this.inDialog) {
      this.calendarTarget.style.left = `${Math.max(viewportLeft + margin, Math.min(field.left, viewportRight - calendar.width - margin))}px`
      this.calendarTarget.style.top = `${Math.max(top, Math.min(field.bottom + margin, bottom - calendar.height))}px`
      return
    }
    if (ensureVisible === true) {
      const missing = field.bottom + margin + calendar.height - bottom
      const scroll = Math.min(Math.max(0, missing), Math.max(0, field.top - top))
      if (scroll > 0) {
        const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
        window.scrollBy({ top: scroll, behavior: reducedMotion ? "instant" : "smooth" })
        field = this.textInput.getBoundingClientRect()
      }
    }
    this.calendarTarget.style.left = `${Math.max(viewportLeft + margin, Math.min(field.left, viewportRight - calendar.width - margin)) - field.left}px`
  }

  close() {
    const focused = this.calendarTarget.contains(document.activeElement)
    if (this.inDialog) this.calendarTarget.hidePopover()
    this.calendarTarget.hidden = true
    this.textInput.setAttribute("aria-expanded", "false")
    if (focused) this.textInput.focus({ preventScroll: true })
  }

  focusout(event) {
    if (!this.element.contains(event.relatedTarget)) this.close()
  }

  outside(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  previous() { this.moveMonth(-1) }
  next() { this.moveMonth(1) }

  moveMonth(offset) {
    this.visibleMonth.setMonth(this.visibleMonth.getMonth() + offset)
    this.render()
    this.position(true)
  }

  iso(date) {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`
  }

  today() { this.select(this.iso(new Date())) }

  selectable(value) {
    return !((this.inputTarget.min && value < this.inputTarget.min) || (this.inputTarget.max && value > this.inputTarget.max))
  }

  select(value) {
    if (!this.selectable(value)) return
    this.inputTarget.value = value
    this.syncDisplay()
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.close()
    this.textInput.focus()
  }

  keydown(event) {
    if (event.key === "Escape" && !this.calendarTarget.hidden) {
      event.preventDefault()
      event.stopPropagation()
      this.close()
    } else if (event.key === "ArrowDown" && event.altKey && event.target === this.textInput) {
      event.preventDefault()
      this.open(event)
      const day = this.daysTarget.querySelector(`button[data-date="${this.focusDate}"]:not(:disabled)`) || this.daysTarget.querySelector("button:not(:disabled)")
      day?.focus({ preventScroll: true })
    }
  }

  render() {
    const year = this.visibleMonth.getFullYear()
    const month = this.visibleMonth.getMonth()
    this.monthTarget.textContent = this.visibleMonth.toLocaleDateString("de-DE", { month: "long", year: "numeric" })
    const offset = (this.visibleMonth.getDay() + 6) % 7
    const count = new Date(year, month + 1, 0).getDate()
    const today = this.iso(new Date())
    const partialDay = this.textInput.value.trim().match(/^(\d{1,2})\.?$/)
    const suggestedDay = partialDay ? Number(partialDay[1]) : 0
    const suggestion = suggestedDay >= 1 && suggestedDay <= count
      ? this.iso(new Date(year, month, suggestedDay)) : ""
    const selected = this.inputTarget.value || (this.selectable(suggestion) ? suggestion : "")
    if (selected) this.focusDate = selected
    this.todayButtonTarget.disabled = !this.selectable(today)
    const cells = []
    for (let index = 0; index < offset; index++) cells.push(document.createElement("span"))
    for (let day = 1; day <= count; day++) {
      const date = new Date(year, month, day)
      const value = this.iso(date)
      const button = document.createElement("button")
      button.type = "button"
      button.textContent = day
      button.setAttribute("data-date", value)
      button.setAttribute("aria-label", date.toLocaleDateString("de-DE", { dateStyle: "full" }))
      button.setAttribute("aria-pressed", String(value === selected))
      if (value === today) button.setAttribute("aria-current", "date")
      button.disabled = !this.selectable(value)
      button.addEventListener("click", () => this.select(value))
      cells.push(button)
    }
    this.daysTarget.replaceChildren(...cells)
  }
}
