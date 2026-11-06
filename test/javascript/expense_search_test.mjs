import { readFileSync } from "node:fs"
import test from "node:test"
import assert from "node:assert/strict"
const source = readFileSync(new URL("../../app/javascript/expense_search.js", import.meta.url), "utf8")
const { searchExpenses } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`)
const categories = [
  { key: "expense_insurance", label: "Beiträge, Gebühren und Versicherungen", terms: "applecare betriebshaftpflicht" },
  { key: "expense_it", label: "Software und Online-Dienste", terms: "vps hosting servermiete softwareabo ionos" },
  { key: "expense_phone", label: "Telefon und Internet", terms: "telefonrechnung mobilfunk congstar ionos" },
  { key: "expense_supplies", label: "Büromaterial", terms: "papier stifte buerobedarf" },
  { key: "expense_repairs", label: "Wartung und Reparaturen", terms: "reparatur wartung" }
]

test("free descriptions match synonyms without choosing a category", () => {
  for (const query of ["VPS bei IONOS", "Ich möchte Servermiete buchen", "Software-Abo"]) {
    const result = searchExpenses(query, categories)
    assert.equal(result.type, "matches")
    assert.equal(result.matches[0].key, "expense_it")
  }
  assert.equal(searchExpenses("BUEROMATERIAL", categories).matches[0].key, "expense_supplies")
  assert.equal(searchExpenses("Meine Telefonrechnung", categories).matches[0].key, "expense_phone")
})

test("ambiguous providers return alternatives and unknown input has no fallback", () => {
  assert.equal(searchExpenses("IONOS", categories).matches.length, 2)
  for (const query of ["unbekanntxyz", "Ich möchte eine Rechnung buchen", "<script>alert(1)</script>"]) {
    assert.equal(searchExpenses(query, categories).type, "none")
  }
  assert.equal(searchExpenses("", categories).type, "empty")
})

test("equipment asks about its purpose while ongoing expenses remain searchable", () => {
  for (const query of ["Computer", "Kamera für meine Arbeit", "Laptop zum Weiterverkauf", "Server gekauft"]) {
    assert.equal(searchExpenses(query, categories).type, "equipment")
  }
  assert.equal(searchExpenses("Computer Reparatur", categories).matches[0].key, "expense_repairs")
  assert.equal(searchExpenses("VPS Server Hosting", categories).matches[0].key, "expense_it")
})

test("AppleCare spelling variants suggest insurance and explain mixed use", () => {
  for (const query of ["AppleCare+", "Apple Care+", "AppleCare Plus für mein iPhone", "AppleCare+ für MacBook"]) {
    const result = searchExpenses(query, categories)
    assert.equal(result.type, "matches")
    assert.equal(result.matches[0].key, "expense_insurance")
    assert.equal(result.note, "Versicherung für dein Gerät. Nutzt du das Gerät auch privat, berücksichtige nur den betrieblichen Anteil.")
  }
  assert.equal(searchExpenses("Telefonrechnung", categories).note, "")
  assert.equal(searchExpenses("Apple Computer", categories).type, "equipment")
})
