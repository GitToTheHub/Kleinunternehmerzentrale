import { Controller } from "@hotwired/stimulus"
import { searchExpenses } from "expense_search"

export default class extends Controller {
  static targets = ["query", "note", "status", "results", "question", "own", "resale", "more"]
  static values = { categories: Array }

  connect() { this.search() }

  reset() {
    this.element.open = false
    this.queryTarget.value = ""
    this.search()
  }

  search() {
    const result = searchExpenses(this.queryTarget.value, this.categoriesValue)
    this.resultsTarget.replaceChildren()
    this.questionTarget.hidden = result.type !== "equipment"
    this.ownTarget.hidden = true
    this.resaleTarget.hidden = true
    this.moreTarget.hidden = true
    this.noteTarget.textContent = result.note || ""
    this.noteTarget.hidden = !result.note
    this.matches = result.matches
    this.statusTarget.textContent = ({ empty: "", none: "Kein passender Treffer. Beschreibe den Kauf anders oder wähle oben einen Ausgabenbereich und eine Ausgabenart.", equipment: "Wofür hast du den Gegenstand gekauft?", matches: `${result.matches.length} passende Ausgabenarten. Wähle selbst den passenden Treffer.` })[result.type]
    this.renderMatches(5)
  }

  renderMatches(limit) {
    this.resultsTarget.replaceChildren()
    this.matches.slice(0, limit).forEach(category => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "expense-search-result"
      const title = document.createElement("strong")
      title.textContent = category.label
      button.append(title)
      if (category.example) {
        const example = document.createElement("span")
        example.textContent = category.example
        button.append(example)
      }
      button.addEventListener("click", () => this.choose(category.key, category.label))
      this.resultsTarget.append(button)
    })
    this.moreTarget.hidden = this.matches.length <= limit
  }

  showAll() { this.renderMatches(this.matches.length) }

  ownEquipment() {
    this.ownTarget.hidden = false
    this.resaleTarget.hidden = true
    this.statusTarget.textContent = "Eigene Arbeitsmittel und Ausstattung erfasst du im Anlageverzeichnis. Dort werden die steuerlich abziehbaren Kosten berücksichtigt."
  }

  resaleEquipment() {
    this.ownTarget.hidden = true
    this.resaleTarget.hidden = false
    this.statusTarget.textContent = "Zum Weiterverkauf gekaufte Gegenstände können zum Wareneinkauf gehören. Prüfe, ob das auf deinen Einkauf zutrifft."
  }

  chooseGoods() {
    const category = this.categoriesValue.find(item => item.key === "expense_goods")
    if (category) this.choose(category.key, category.label)
  }

  choose(key, label) {
    this.dispatch("choose", { detail: { key } })
    this.statusTarget.textContent = `Ausgewählt: ${label}. Prüfe die Ausgabenart und ergänze deinen Eintrag.`
  }
}
