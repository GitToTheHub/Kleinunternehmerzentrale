export const normalize = text => String(text).toLowerCase().replace(/ä/g, "ae").replace(/ö/g, "oe").replace(/ü/g, "ue").replace(/ß/g, "ss").normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]+/g, " ").trim()
const stopwords = new Set("ich habe moechte buchen eine einen einer einem mein meine meinen meinem fuer von bei mit und oder die der das den dem des ist zum zur bezahlt gekauft rechnung kosten betrieb betrieblich euro".split(" "))

export function searchExpenses(query, categories) {
  const text = normalize(query).replace(/\bapple care\b/g, "applecare")
  const appleCare = /\bapplecare\b/.test(text)
  const words = text.split(" ").filter(word => word.length >= 3 && !stopwords.has(word))
  if (!words.length) return { type: text ? "none" : "empty", matches: [] }
  const equipment = /\b(computer|mac|macbook|iphone|laptop|notebook|smartphone|kamera|maschine|werkzeug|drucker|hardware|server)\b/.test(text)
  const ongoing = /\b(reparatur|reparaturen|wartung|hosting|vps|servermiete|cloud|software|lizenz|toner|papier|druckerpapier|druckerpatrone|miete|leasing)\b/.test(text)
  if (equipment && !ongoing && !appleCare) return { type: "equipment", matches: [] }
  const matches = categories.map(category => {
    const terms = normalize(`${category.label} ${category.terms} ${category.example || ""}`).split(" ")
    const score = words.reduce((sum, word) => sum + (terms.some(term => term === word || (word.length >= 4 && (term.startsWith(word) || word.startsWith(term)))) ? 1 : 0), 0)
    return { ...category, score }
  }).filter(category => category.score > 0).sort((a, b) => b.score - a.score)
  return { type: matches.length ? "matches" : "none", matches, note: appleCare ? "Versicherung für dein Gerät. Nutzt du das Gerät auch privat, berücksichtige nur den betrieblichen Anteil." : "" }
}
