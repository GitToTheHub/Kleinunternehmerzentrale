import { readFileSync } from "node:fs"
import { runInNewContext } from "node:vm"
import test from "node:test"
import assert from "node:assert/strict"

const source = readFileSync(new URL("../../app/javascript/e_invoice.js", import.meta.url), "utf8").replaceAll("export function", "function")
const { decodeInvoiceXml, formatInvoiceDate, formatInvoiceNumber, formatInvoiceMoney } = runInNewContext(`${source}\n({decodeInvoiceXml, formatInvoiceDate, formatInvoiceNumber, formatInvoiceMoney})`, { TextDecoder, Intl })

test("invoice XML decoding handles UTF-8, UTF-16 and declared legacy encodings", () => {
  const xml = "<Name>Müller</Name>"
  assert.equal(decodeInvoiceXml(new TextEncoder().encode(xml)), xml)
  const utf16 = Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from(xml, "utf16le")])
  assert.equal(decodeInvoiceXml(utf16), xml)
  const latin1 = '<?xml version="1.0" encoding="ISO-8859-1"?><Name>Müller</Name>'
  assert.equal(decodeInvoiceXml(Buffer.from(latin1, "latin1")), latin1)
  assert.throws(() => decodeInvoiceXml(Uint8Array.from([0xc3, 0x28])), /Zeichenkodierung/)
})

test("invoice dates display without timezone shifts", () => {
  assert.equal(formatInvoiceDate("20261007"), "07.10.2026")
  assert.equal(formatInvoiceDate("2026-10-07"), "07.10.2026")
  assert.equal(formatInvoiceDate(""), "")
  assert.equal(formatInvoiceDate("unbekannt"), "unbekannt")
})

test("money keeps zero, negative values and the invoice currency", () => {
  assert.match(formatInvoiceMoney("0.00", "EUR"), /0,00/)
  assert.match(formatInvoiceMoney("-119.50", "EUR"), /-119,50/)
  assert.match(formatInvoiceMoney("119.50", "USD"), /119,50.*\$/)
  assert.equal(formatInvoiceMoney("", "EUR"), "—")
  assert.equal(formatInvoiceMoney("12.00", ""), "12.00")
  assert.equal(formatInvoiceMoney("invalid", "EUR"), "invalid EUR")
  assert.equal(formatInvoiceNumber("1.250"), "1,25")
})
