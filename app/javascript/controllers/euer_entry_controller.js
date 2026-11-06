import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dateField", "areaSummary", "areaName", "areaCards", "areaEdit", "typePicker", "typeSummary", "typeName", "typeDescription", "typeCards", "typeOptions", "typeEdit", "categoryLabel", "expenseGroupField", "expenseGroup", "categoryChoice", "expenseExample", "expenseSearch", "kindDescription", "kindExample", "kindExampleRow", "kindDetail", "kindIcon", "kindSummary", "kindLabel", "kindChange", "kindChoices", "kindCancel", "fields", "mixedToggle", "mixedPanel", "businessPercent", "usageNotes", "mixedPreview", "mixedUseField", "kind", "dateLabel", "amountLabel", "amountHint", "descriptionLabel", "descriptionHint", "category", "categoryField", "categoryHelp", "context", "account", "accountLabel", "reversal", "expenseField", "cashField", "reversalField", "invoiceField", "invoice", "foreignPaymentHint", "amount", "reference", "description", "submit"]

  connect() {
    this.categoryOptions = Array.from(this.categoryTarget.options, option => option.cloneNode(true))
    this.refresh()
    this.closeKinds()
  }

  disconnect() {
    const selected = this.categoryTarget.value
    this.categoryTarget.replaceChildren(...this.categoryOptions.map(option => option.cloneNode(true)))
    this.categoryTarget.value = selected
  }

  editExpenseGroup(event) { this.areaOpen = true; this.refresh(); this.focusExpenseChoices(this.areaCardsTarget, event) }
  editExpenseType(event) { this.typeOpen = true; this.refresh(); this.focusExpenseChoices(this.typeCardsTarget, event) }

  focusExpenseChoices(container, event) {
    if (event?.type === "click" && event.detail > 0) container.focus()
    else container.querySelector("input:checked, input")?.focus()
  }

  areaChosen(event) {
    if (event.type === "change" && this.areaCardsTarget.hidden) return
    if (this.expenseGroupTarget.value !== event.currentTarget.value) this.categoryTarget.value = ""
    this.expenseGroupTarget.value = event.currentTarget.value
    this.areaOpen = false
    this.typeOpen = !this.categoryTarget.value
    this.refresh()
    if (this.categoryTarget.value) this.areaEditTarget.focus()
    else this.focusExpenseChoices(this.typeCardsTarget, event)
  }

  syncExpenseCards(expense) {
    const group = this.expenseGroupTarget.value
    const selected = this.categoryTarget.value
    this.areaSummaryTarget.hidden = !group
    this.areaNameTarget.textContent = group
    this.areaCardsTarget.hidden = !!group && !this.areaOpen
    this.areaEditTarget.setAttribute("aria-expanded", String(!this.areaCardsTarget.hidden))
    this.areaCardsTarget.querySelectorAll("input").forEach(input => { input.checked = input.value === group; input.required = expense; input.disabled = !expense })
    this.typePickerTarget.hidden = !expense || !group
    this.typeSummaryTarget.hidden = !selected
    this.typeCardsTarget.hidden = !group || (!!selected && !this.typeOpen)
    this.typeEditTarget.setAttribute("aria-expanded", String(!this.typeCardsTarget.hidden))
    this.typeOptionsTarget.replaceChildren()
    if (!expense || !group) return
    for (const option of this.categoryTarget.options) {
      if (!option.value) continue
      const label = document.createElement("label")
      label.className = "booking-type-option"
      const radio = document.createElement("input")
      radio.type = "radio"; radio.name = "expense_type_choice"; radio.value = option.value
      radio.required = true; radio.checked = option.value === selected
      const choose = event => {
        if (event.type === "change" && this.typeCardsTarget.hidden) return
        this.categoryTarget.value = option.value
        this.typeOpen = false
        this.refresh()
        this.typeEditTarget.focus()
      }
      radio.addEventListener("click", choose)
      radio.addEventListener("change", choose)
      const text = document.createElement("span")
      const title = document.createElement("strong")
      title.textContent = option.dataset.label
      const example = document.createElement("small")
      example.textContent = option.dataset.example || ""
      text.append(title, example); label.append(radio, text)
      this.typeOptionsTarget.append(label)
      if (radio.checked) {
        this.typeNameTarget.textContent = option.dataset.label
        this.typeDescriptionTarget.textContent = option.dataset.example || ""
      }
    }
  }

  expenseGroupChanged() {
    this.categoryTarget.value = ""
    this.refresh()
  }

  chooseExpenseCategory({ detail }) {
    if (this.selectedKind?.value !== "expense") return
    if (!this.categoryOptions.some(option => option.value === detail.key && option.dataset.kinds.split(" ").includes("expense"))) return
    const option = this.categoryOptions.find(item => item.value === detail.key)
    this.expenseGroupTarget.value = option.dataset.expenseGroup
    this.categoryTarget.value = ""
    this.refresh()
    this.categoryTarget.value = detail.key
    this.refresh()
    this.areaOpen = false
    this.typeOpen = false
    this.syncExpenseCards(true)
    this.typeEditTarget.focus()
  }

  get selectedKind() {
    return this.kindTargets.find(input => input.checked)
  }

  editKind() {
    this.kindChoicesTarget.hidden = false
    this.kindChangeTarget.setAttribute("aria-expanded", "true")
    this.selectedKind?.focus()
  }

  closeKinds() {
    const choice = this.selectedKind
    this.kindSummaryTarget.hidden = !choice
    this.kindChoicesTarget.hidden = !!choice
    this.kindCancelTarget.hidden = !choice
    this.kindChangeTarget.setAttribute("aria-expanded", "false")
    if (choice) {
      this.kindLabelTarget.textContent = choice.dataset.kindLabel
      this.kindDescriptionTarget.textContent = choice.dataset.kindHint
      this.kindExampleTarget.textContent = choice.dataset.kindExample || ""
      this.kindExampleRowTarget.hidden = !choice.dataset.kindExample
      this.kindDetailTarget.textContent = choice.dataset.kindDetail
      const icon = choice.closest("label").querySelector("svg")
      if (icon) this.kindIconTarget.replaceChildren(icon.cloneNode(true))
    }
  }

  kindChanged(event) {
    // A mouse click also dispatches change; keyboard changes still work on their own.
    if (event?.type === "change" && this.kindChoicesTarget.hidden) return
    if (this.hasExpenseSearchTarget) this.expenseSearchTarget.dispatchEvent(new Event("expense-search:reset"))
    this.refresh()
    this.closeKinds()
    this.kindChangeTarget.focus()
  }

  refresh() {
    const choice = this.selectedKind
    this.fieldsTarget.hidden = !choice
    this.fieldsTarget.disabled = !choice
    if (!choice) return
    const kind = this.selectedKind.value
    if (this.hasExpenseSearchTarget) this.expenseSearchTarget.hidden = kind !== "expense"
    this.dateLabelTarget.textContent = this.selectedKind.dataset.dateLabel
    const selected = this.categoryTarget.value
    const matching = this.categoryOptions.filter(option => option.value && option.dataset.kinds.split(" ").includes(kind))
    this.expenseGroupFieldTarget.hidden = kind !== "expense"
    this.expenseGroupTarget.required = false
    this.expenseGroupTarget.disabled = kind !== "expense"
    if (kind === "expense") {
      const current = matching.find(option => option.value === selected)
      if (current) this.expenseGroupTarget.value = current.dataset.expenseGroup
      const group = this.expenseGroupTarget.value
      const options = matching.filter(option => option.dataset.expenseGroup === group).map(option => {
        const copy = option.cloneNode(true)
        copy.textContent = option.dataset.label
        return copy
      })
      this.categoryTarget.replaceChildren(new Option("Bitte wähle die Ausgabenart", ""), ...options)
      this.categoryTarget.value = options.some(option => option.value === selected) ? selected : ""
      this.categoryChoiceTarget.hidden = true
      this.categoryTarget.disabled = !group
      const chosen = options.find(option => option.value === selected)
      this.expenseExampleTarget.hidden = !chosen?.dataset.example
      this.expenseExampleTarget.textContent = chosen?.dataset.example ? `Zum Beispiel: ${chosen.dataset.example}.` : ""
    } else {
      this.expenseGroupTarget.value = ""
      this.categoryChoiceTarget.hidden = false
      this.categoryTarget.disabled = false
      this.expenseExampleTarget.hidden = true
      this.categoryTarget.replaceChildren(...matching.map(option => option.cloneNode(true)))
      this.categoryTarget.value = matching.some(option => option.value === selected) ? selected : matching[0]?.value || ""
    }
    this.categoryLabelTarget.textContent = this.selectedKind.dataset.categoryLabel
    if (this.hasDateFieldTarget) this.dateFieldTarget.hidden = kind === "expense" && !this.expenseGroupTarget.value
    this.syncExpenseCards(kind === "expense")
    const cash = ["income", "expense"].includes(kind)
    const equity = ["deposit", "withdrawal"].includes(kind)
    this.categoryTarget.required = !equity && kind !== "expense"
    this.show(this.categoryFieldTarget, !equity)
    this.categoryHelpTargets.forEach(help => {
      const kinds = (help.dataset.kinds || "").split(" ").filter(Boolean)
      help.hidden = equity || help.dataset.category !== this.categoryTarget.value || (kinds.length > 0 && !kinds.includes(kind))
    })
    this.show(this.expenseFieldTarget, kind === "expense")
    if (["expense_meals", "expense_gifts", "expense_home_office", "expense_limited"].includes(this.categoryTarget.value)) this.expenseFieldTarget.open = true
    if (this.hasMixedUseFieldTarget) {
      this.mixedUseFieldTarget.hidden = kind !== "expense"
      if (kind !== "expense") {
        const percent = this.mixedUseFieldTarget.querySelector('[name$="[business_percent]"]')
        if (percent) percent.value = "100"
        const notes = this.mixedUseFieldTarget.querySelector("textarea")
        if (notes) notes.value = ""
      }
    }
    this.cashFieldTargets.forEach(field => this.show(field, cash))
    if (kind === "noncash_deposit") this.reversalTarget.checked = false
    this.updateMixedUse()
    this.updateHints()
  }

  updateMixedUse() {
    if (!this.hasMixedToggleTarget) return
    const mixed = this.selectedKind.value === "expense" && this.mixedToggleTarget.checked
    this.mixedPanelTarget.hidden = !mixed
    if (!mixed) {
      this.businessPercentTarget.value = "100"
      this.usageNotesTarget.value = ""
    }
    this.businessPercentTarget.required = mixed
    this.usageNotesTarget.required = mixed
    this.updateMixedPreview()
  }

  updateMixedPreview() {
    if (!this.hasMixedPreviewTarget || this.mixedPanelTarget.hidden) return
    const number = value => Number(value.includes(",") ? value.trim().replace(/\./g, "").replace(",", ".") : value.trim())
    const amount = number(this.amountTarget.value)
    const percent = Number(this.businessPercentTarget.value.replace(",", "."))
    if (!(amount > 0 && percent > 0 && percent <= 100)) {
      this.mixedPreviewTarget.textContent = "Gib Rechnungsbetrag und betrieblichen Anteil ein, um die Aufteilung zu sehen."
      return
    }
    const business = Math.round(amount * percent) / 100
    const money = value => value.toLocaleString("de-DE", { style: "currency", currency: "EUR" })
    this.mixedPreviewTarget.textContent = `${money(business)} betrieblich, ${money(amount - business)} privat. ` +
      (this.accountTarget.value === "private" ? `${money(business)} werden zusätzlich als Einlage berücksichtigt.` : `${money(amount - business)} werden zusätzlich als Entnahme berücksichtigt.`) + " Dafür keinen zweiten Vorgang anlegen."
  }

  updateHints() {
    this.updateMixedPreview()
    const kind = this.selectedKind.value
    const category = this.categoryTarget.value
    const copy = this.selectedKind.dataset
    const incoming = (kind === "income" && !this.reversalTarget.checked) || (kind === "expense" && this.reversalTarget.checked)
    this.accountLabelTarget.textContent = kind === "income" ? "Zahlungsart" : (incoming ? "Geld erhalten auf" : "Bezahlt von")
    this.accountTarget.querySelector('option[value="business"]').textContent = kind === "income" ? "Geschäftskonto" : "Betriebskonto / Betriebskasse"
    const cashOption = this.accountTarget.querySelector('option[value="cash"]')
    cashOption.hidden = cashOption.disabled = kind !== "income"
    if (kind !== "income" && this.accountTarget.value === "cash") this.accountTarget.value = "business"
    this.accountTarget.dispatchEvent(new CustomEvent("payment-kind-change", { bubbles: true }))
    this.accountTarget.querySelector('option[value="private"]').textContent = incoming ? "Privatkonto" : "Privatkonto / privat bezahlt"
    const canLinkInvoice = kind === "income" && !this.reversalTarget.checked && ["income_small", "asset_income"].includes(category)
    this.show(this.invoiceFieldTarget, canLinkInvoice && this.invoiceTarget.options.length > 1)
    const linked = canLinkInvoice && !!this.invoiceTarget.value
    this.foreignPaymentHintTarget.hidden = !linked || this.invoiceTarget.selectedOptions[0].dataset.foreign !== "true"
    this.submitTarget.textContent = linked ? this.invoiceTarget.selectedOptions[0].dataset.paymentAction : "Speichern"
    this.dateLabelTarget.textContent = copy.dateLabel
    for (const name of ["amountLabel", "amountHint", "descriptionLabel", "descriptionHint"]) {
      this[`${name}Target`].textContent = copy[name]
    }
    if (this.reversalTarget.checked) {
      this.dateLabelTarget.textContent = kind === "income" ? "Datum der Rückzahlung" : kind === "expense" ? "Datum der Erstattung" : "Datum der Rückgängigmachung"
      this.amountLabelTarget.textContent = "Erstatteter / zurückgezahlter Betrag in Euro"
      this.amountHintTarget.textContent = "Trage den Betrag positiv ein. Die App zieht ihn vom ursprünglichen Vorgang ab."
      this.descriptionHintTarget.textContent = "Beschreibe die Erstattung oder Rückzahlung und den ursprünglichen Vorgang."
    } else if (category === "vehicle_use") {
      this.amountLabelTarget.textContent = "Steuerlicher Wert der privaten Fahrzeugnutzung in Euro"
      this.amountHintTarget.textContent = "Trage den steuerlich ermittelten Wert der privaten Fahrzeugnutzung ein."
    }
    const matches = (list, value) => !list || list.split(" ").includes(value)
    this.contextTargets.forEach(hint => {
      const rules = hint.dataset
      hint.hidden = !matches(rules.kinds, kind) || !matches(rules.categories, category) ||
        (rules.excludedCategories && rules.excludedCategories.split(" ").includes(category)) ||
        !matches(rules.accounts, this.accountTarget.value) ||
        (rules.reversal !== undefined && rules.reversal !== String(this.reversalTarget.checked))
    })
  }

  invoiceChanged() {
    const option = this.invoiceTarget.selectedOptions[0]
    if (option.value) {
      this.amountTarget.value = Number(option.dataset.amount).toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2, useGrouping: false })
      this.referenceTarget.value = option.dataset.reference
      this.descriptionTarget.value = option.dataset.description
    }
    this.updateHints()
  }

  show(field, visible) {
    field.hidden = !visible
    // Hidden values must not survive a kind change (e.g. deductible percentage
    // when changing an expense to an income). Submit neutral values explicitly.
    if (!visible) {
      for (const input of field.querySelectorAll("input, select")) {
        if (["checkbox", "radio"].includes(input.type)) input.checked = false
        else if (input.name.endsWith("[vat_amount]")) input.value = "0"
        else if (input.name.endsWith("[payment_account]")) input.value = "business"
        else input.value = ""
      }
    }
  }
}
