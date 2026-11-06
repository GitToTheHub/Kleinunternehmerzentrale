export function parsePrice(value) {
  const input = String(value ?? "").trim()
  const german = /^(?:\d+|\d{1,3}(?:\.\d{3})+),\d{1,2}$/
  if (input.includes(",")) return german.test(input) ? Number(input.replaceAll(".", "").replace(",", ".")) : NaN
  return /^\d+(?:\.\d{1,2})?$/.test(input) ? Number(input) : NaN
}

export function formatPrice(value) {
  const number = parsePrice(value)
  return Number.isFinite(number) ? number.toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2, useGrouping: false }) : String(value ?? "")
}
