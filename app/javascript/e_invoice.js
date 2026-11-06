// Read invoice data without changing amounts, executing markup or making requests.
const UBL_INVOICE = "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
const UBL_CREDIT = "urn:oasis:names:specification:ubl:schema:xsd:CreditNote-2"
const CII = "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100"

export function decodeInvoiceXml(bytes) {
  let encoding = "utf-8"
  if (bytes[0] === 0xff && bytes[1] === 0xfe) encoding = "utf-16le"
  else if (bytes[0] === 0xfe && bytes[1] === 0xff) encoding = "utf-16be"
  else if (bytes[0] === 0x3c && bytes[1] === 0) encoding = "utf-16le"
  else if (bytes[0] === 0 && bytes[1] === 0x3c) encoding = "utf-16be"
  else encoding = new TextDecoder().decode(bytes.slice(0, 200)).match(/<\?xml[^>]*encoding=["']([^"']+)["']/i)?.[1] || encoding
  try { return new TextDecoder(encoding, { fatal: true }).decode(bytes) }
  catch { throw new Error("Die Zeichenkodierung der XML-Datei konnte nicht gelesen werden.") }
}

function nodes(node, path) {
  return path.split("/").reduce((parents, name) => parents.flatMap(parent =>
    Array.from(parent?.children || []).filter(child => child.localName === name)), [node])
}
function nodeAt(node, path) { return nodes(node, path)[0] }
function value(node, ...paths) {
  for (const path of paths) {
    const text = nodeAt(node, path)?.textContent.trim()
    if (text) return text
  }
  return ""
}
function values(node, path) { return nodes(node, path).map(item => item.textContent.trim()).filter(Boolean) }
function amount(node, path, label) { return [label, value(node, path)] }

function ublParty(party) {
  const address = nodeAt(party, "PostalAddress")
  return {
    name: value(party, "PartyLegalEntity/RegistrationName", "PartyName/Name"),
    address: [value(address, "StreetName"), value(address, "AdditionalStreetName"), ...values(address, "AddressLine/Line"),
      [value(address, "PostalZone"), value(address, "CityName")].filter(Boolean).join(" "), value(address, "Country/IdentificationCode")].filter(Boolean),
    contact: value(party, "Contact/Name"), email: value(party, "Contact/ElectronicMail", "EndpointID"),
    phone: value(party, "Contact/Telephone"), identifiers: nodes(party, "PartyTaxScheme").map(tax => value(tax, "CompanyID")),
  }
}

function ciiParty(party) {
  const address = nodeAt(party, "PostalTradeAddress")
  return {
    name: value(party, "Name"),
    address: [value(address, "LineOne"), value(address, "LineTwo"), value(address, "LineThree"),
      [value(address, "PostcodeCode"), value(address, "CityName")].filter(Boolean).join(" "), value(address, "CountryID")].filter(Boolean),
    contact: value(party, "DefinedTradeContact/PersonName", "DefinedTradeContact/DepartmentName"),
    email: value(party, "DefinedTradeContact/EmailURIUniversalCommunication/URIID", "URIUniversalCommunication/URIID"),
    phone: value(party, "DefinedTradeContact/TelephoneUniversalCommunication/CompleteNumber"),
    identifiers: values(party, "SpecifiedTaxRegistration/ID"),
  }
}

function ublAdjustments(node) {
  return nodes(node, "AllowanceCharge").map(adjustment => ({
    label: value(adjustment, "ChargeIndicator") === "true" ? "Zuschlag" : "Nachlass",
    reason: value(adjustment, "AllowanceChargeReason"), amount: value(adjustment, "Amount"),
  }))
}

function ciiAdjustments(node) {
  return nodes(node, "SpecifiedTradeAllowanceCharge").map(adjustment => ({
    label: value(adjustment, "ChargeIndicator/Indicator") === "true" ? "Zuschlag" : "Nachlass",
    reason: value(adjustment, "Reason"), amount: value(adjustment, "ActualAmount"),
  }))
}

function parseUbl(root) {
  const credit = root.localName === "CreditNote"
  const total = nodeAt(root, "LegalMonetaryTotal")
  const period = nodeAt(root, "InvoicePeriod")
  return {
    format: "UBL", type: credit ? "Gutschrift" : "Rechnung", number: value(root, "ID"),
    currency: value(root, "DocumentCurrencyCode"), issued: value(root, "IssueDate"), due: value(root, "DueDate", "PaymentMeans/PaymentDueDate"),
    service: value(root, "Delivery/ActualDeliveryDate"), start: value(period, "StartDate"), end: value(period, "EndDate"),
    seller: ublParty(nodeAt(root, "AccountingSupplierParty/Party")), buyer: ublParty(nodeAt(root, "AccountingCustomerParty/Party")),
    references: [["Käuferreferenz / Leitweg-ID", value(root, "BuyerReference")], ["Bestellnummer", value(root, "OrderReference/ID")],
      ["Vertragsnummer", value(root, "ContractDocumentReference/ID")], ["Vorherige Rechnung", value(root, "BillingReference/InvoiceDocumentReference/ID")]],
    lines: nodes(root, credit ? "CreditNoteLine" : "InvoiceLine").map(line => {
      const quantity = nodeAt(line, credit ? "CreditedQuantity" : "InvoicedQuantity")
      return {
        id: value(line, "ID"), name: value(line, "Item/Name"), description: value(line, "Item/Description"),
        quantity: quantity?.textContent.trim() || "", unit: quantity?.getAttribute("unitCode") || "",
        price: value(line, "Price/PriceAmount"), base: value(line, "Price/BaseQuantity"), net: value(line, "LineExtensionAmount"),
        tax: value(line, "Item/ClassifiedTaxCategory/Percent"), adjustments: ublAdjustments(line),
      }
    }),
    totals: [amount(total, "LineExtensionAmount", "Summe der Positionen (netto)"), amount(total, "AllowanceTotalAmount", "Nachlässe"),
      amount(total, "ChargeTotalAmount", "Zuschläge"), amount(total, "TaxExclusiveAmount", "Gesamt netto"),
      amount(root, "TaxTotal/TaxAmount", "Umsatzsteuer"), amount(total, "TaxInclusiveAmount", "Gesamtbetrag"),
      amount(total, "PrepaidAmount", "Bereits bezahlt"), amount(total, "PayableRoundingAmount", "Rundung"), amount(total, "PayableAmount", "Zu zahlen")],
    taxes: nodes(root, "TaxTotal/TaxSubtotal").map(tax => ({
      rate: value(tax, "TaxCategory/Percent"), category: value(tax, "TaxCategory/ID"), basis: value(tax, "TaxableAmount"),
      amount: value(tax, "TaxAmount"), reason: value(tax, "TaxCategory/TaxExemptionReason"),
    })),
    payments: nodes(root, "PaymentMeans").map(payment => ({
      account: value(payment, "PayeeFinancialAccount/ID"), holder: value(payment, "PayeeFinancialAccount/Name"),
      bic: value(payment, "PayeeFinancialAccount/FinancialInstitutionBranch/ID"), reference: value(payment, "PaymentID"),
      note: value(payment, "InstructionNote"), code: value(payment, "PaymentMeansCode"),
    })),
    terms: values(root, "PaymentTerms/Note"), notes: values(root, "Note"), adjustments: ublAdjustments(root),
  }
}

function parseCii(root) {
  const header = nodeAt(root, "ExchangedDocument")
  const transaction = nodeAt(root, "SupplyChainTradeTransaction")
  const agreement = nodeAt(transaction, "ApplicableHeaderTradeAgreement")
  const settlement = nodeAt(transaction, "ApplicableHeaderTradeSettlement")
  const total = nodeAt(settlement, "SpecifiedTradeSettlementHeaderMonetarySummation")
  const period = nodeAt(settlement, "BillingSpecifiedPeriod")
  const type = value(header, "TypeCode")
  return {
    format: "CII", type: type === "381" ? "Gutschrift" : type === "384" ? "Korrigierte Rechnung" : "Rechnung", number: value(header, "ID"),
    currency: value(settlement, "InvoiceCurrencyCode"), issued: value(header, "IssueDateTime/DateTimeString"),
    due: value(settlement, "SpecifiedTradePaymentTerms/DueDateDateTime/DateTimeString"),
    service: value(transaction, "ApplicableHeaderTradeDelivery/ActualDeliverySupplyChainEvent/OccurrenceDateTime/DateTimeString"),
    start: value(period, "StartDateTime/DateTimeString"), end: value(period, "EndDateTime/DateTimeString"),
    seller: ciiParty(nodeAt(agreement, "SellerTradeParty")), buyer: ciiParty(nodeAt(agreement, "BuyerTradeParty")),
    references: [["Käuferreferenz / Leitweg-ID", value(agreement, "BuyerReference")], ["Bestellnummer", value(agreement, "BuyerOrderReferencedDocument/IssuerAssignedID")],
      ["Vertragsnummer", value(agreement, "ContractReferencedDocument/IssuerAssignedID")], ["Vorherige Rechnung", value(settlement, "InvoiceReferencedDocument/IssuerAssignedID")]],
    lines: nodes(transaction, "IncludedSupplyChainTradeLineItem").map(line => {
      const quantity = nodeAt(line, "SpecifiedLineTradeDelivery/BilledQuantity")
      const price = nodeAt(line, "SpecifiedLineTradeAgreement/NetPriceProductTradePrice")
      const lineSettlement = nodeAt(line, "SpecifiedLineTradeSettlement")
      return {
        id: value(line, "AssociatedDocumentLineDocument/LineID"), name: value(line, "SpecifiedTradeProduct/Name"), description: value(line, "SpecifiedTradeProduct/Description"),
        quantity: quantity?.textContent.trim() || "", unit: quantity?.getAttribute("unitCode") || "",
        price: value(price, "ChargeAmount"), base: value(price, "BasisQuantity"), net: value(lineSettlement, "SpecifiedTradeSettlementLineMonetarySummation/LineTotalAmount"),
        tax: value(lineSettlement, "ApplicableTradeTax/RateApplicablePercent"), adjustments: ciiAdjustments(lineSettlement),
      }
    }),
    totals: [amount(total, "LineTotalAmount", "Summe der Positionen (netto)"), amount(total, "AllowanceTotalAmount", "Nachlässe"),
      amount(total, "ChargeTotalAmount", "Zuschläge"), amount(total, "TaxBasisTotalAmount", "Gesamt netto"),
      amount(total, "TaxTotalAmount", "Umsatzsteuer"), amount(total, "GrandTotalAmount", "Gesamtbetrag"),
      amount(total, "TotalPrepaidAmount", "Bereits bezahlt"), amount(total, "RoundingAmount", "Rundung"), amount(total, "DuePayableAmount", "Zu zahlen")],
    taxes: nodes(settlement, "ApplicableTradeTax").map(tax => ({
      rate: value(tax, "RateApplicablePercent"), category: value(tax, "CategoryCode"), basis: value(tax, "BasisAmount"),
      amount: value(tax, "CalculatedAmount"), reason: value(tax, "ExemptionReason"),
    })),
    payments: nodes(settlement, "SpecifiedTradeSettlementPaymentMeans").map(payment => ({
      account: value(payment, "PayeePartyCreditorFinancialAccount/IBANID", "PayeePartyCreditorFinancialAccount/ProprietaryID"),
      holder: value(payment, "PayeePartyCreditorFinancialAccount/AccountName"), bic: value(payment, "PayeeSpecifiedCreditorFinancialInstitution/BICID"),
      reference: value(settlement, "PaymentReference"), note: value(payment, "Information"), code: value(payment, "TypeCode"),
    })),
    terms: values(settlement, "SpecifiedTradePaymentTerms/Description"), notes: values(header, "IncludedNote/Content"), adjustments: ciiAdjustments(settlement),
  }
}

export function parseInvoiceXml(xml) {
  if (/<!DOCTYPE|<!ENTITY/i.test(xml)) throw new Error("XML-Dateien mit Dokumenttyp- oder Entity-Deklarationen werden nicht unterstützt.")
  const document = new DOMParser().parseFromString(xml, "application/xml")
  if (document.getElementsByTagName("parsererror").length || !document.documentElement) {
    throw new Error("Die XML-Datei ist beschädigt oder nicht korrekt aufgebaut.")
  }
  if (document.getElementsByTagName("*").length > 30000) throw new Error("Die Rechnung enthält zu viele Daten für diesen Viewer.")
  const root = document.documentElement
  let invoice
  if ((root.localName === "Invoice" && root.namespaceURI === UBL_INVOICE) || (root.localName === "CreditNote" && root.namespaceURI === UBL_CREDIT)) invoice = parseUbl(root)
  else if (root.localName === "CrossIndustryInvoice" && root.namespaceURI === CII) invoice = parseCii(root)
  else throw new Error("Keine unterstützte E-Rechnung gefunden. Bitte wähle eine XRechnung oder eine ZUGFeRD-Rechnung in UBL oder CII.")
  if (!invoice.number) throw new Error("In der Datei wurde keine Rechnungsnummer gefunden.")
  // Preserve access to additional fields without treating uploaded text as HTML.
  invoice.fields = Array.from(document.getElementsByTagName("*")).filter(node => !node.children.length && node.textContent.trim() && !/BinaryObject$/.test(node.localName)).map(node => {
    const path = []
    for (let parent = node; parent && parent !== root; parent = parent.parentElement) path.unshift(parent.localName)
    return [path.join(" / "), node.textContent.trim()]
  })
  return invoice
}

export function formatInvoiceDate(value) {
  const match = value?.match(/^(\d{4})-?(\d{2})-?(\d{2})$/)
  return match ? `${match[3]}.${match[2]}.${match[1]}` : value
}

export function formatInvoiceNumber(value) {
  return value !== "" && Number.isFinite(Number(value)) ? new Intl.NumberFormat("de-DE", { maximumFractionDigits: 10 }).format(Number(value)) : value
}

export function formatInvoiceMoney(value, currency) {
  if (value === "") return "—"
  if (!currency || !/^[A-Z]{3}$/.test(currency) || !Number.isFinite(Number(value))) return [value, currency].filter(Boolean).join(" ")
  return new Intl.NumberFormat("de-DE", { style: "currency", currency }).format(Number(value))
}
