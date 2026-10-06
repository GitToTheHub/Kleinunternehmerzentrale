require "zugpferd"
require "nokogiri"

class XrechnungGenerator
  EXEMPTION_REASON = "Steuerbefreiung für Kleinunternehmer nach § 19 UStG"
  CUSTOMIZATION_ID = "urn:cen.eu:en16931:2017#compliant#urn:xeinkauf.de:kosit:xrechnung_3.0"

  def initialize(invoice)
    @invoice = invoice
  end

  def call
    xml = Zugpferd::CII::Writer.new.write(build_invoice)
    xml = add_seller_tax_number(xml) if @invoice.seller_tax_id_kind == "tax_number"
    xml = add_buyer_order_number(xml) if @invoice.buyer_order_number.present?
    xml = add_billing_period(xml) if @invoice.service_until_on?
    xml = add_cancelled_invoice_reference(xml) if @invoice.cancellation?
    xml
  end

  private

  def build_invoice
    document_class = @invoice.cancellation? ? Zugpferd::Model::CorrectedInvoice : Zugpferd::Model::Invoice
    invoice = document_class.new(
      number: @invoice.invoice_number,
      issue_date: @invoice.issued_on,
      delivery_date: (@invoice.service_on unless @invoice.service_until_on?),
      currency_code: "EUR"
    )
    invoice.customization_id = CUSTOMIZATION_ID
    # XRechnung verlangt eine Käuferreferenz (BT-10). Ohne Leitweg-ID dient die Bestellnummer, sonst die Rechnungsnummer.
    invoice.buyer_reference = @invoice.buyer_leitweg_id.presence || @invoice.buyer_order_number.presence || @invoice.invoice_number
    invoice.seller = trade_party(
      @invoice.seller_name, @invoice.seller_email, @invoice.seller_street,
      @invoice.seller_postal_code, @invoice.seller_city, @invoice.seller_country
    )
    invoice.seller.vat_identifier = @invoice.seller_tax_identifier if @invoice.seller_tax_id_kind == "vat_id"
    invoice.buyer = trade_party(
      @invoice.buyer_name, @invoice.buyer_email, @invoice.buyer_street,
      @invoice.buyer_postal_code, @invoice.buyer_city, @invoice.buyer_country
    )
    invoice.due_date = @invoice.payment_due_on
    invoice.payment_instructions = payment_instructions
    invoice.line_items = @invoice.invoice_lines.map.with_index(1) { |line, index| build_line(line, index) }

    add_totals(invoice)
    invoice
  end

  def add_totals(invoice)
    net = @invoice.net_total
    tax = @invoice.tax_total
    invoice.tax_breakdown = Zugpferd::Model::TaxBreakdown.new(tax_amount: decimal(tax), currency_code: "EUR")
    tax_subtotals.each { |subtotal| invoice.tax_breakdown.subtotals << subtotal }
    invoice.monetary_totals = Zugpferd::Model::MonetaryTotals.new(
      line_extension_amount: decimal(net), tax_exclusive_amount: decimal(net),
      tax_inclusive_amount: decimal(net + tax), payable_amount: decimal(net + tax)
    )
  end

  def tax_subtotals
    unless @invoice.standard_taxed?
      return [ Zugpferd::Model::TaxSubtotal.new(
        taxable_amount: decimal(@invoice.net_total), tax_amount: "0.00", category_code: "E",
        currency_code: "EUR", exemption_reason: EXEMPTION_REASON
      ) ]
    end

    @invoice.tax_groups.map do |group|
      Zugpferd::Model::TaxSubtotal.new(
        taxable_amount: decimal(group[:net]), tax_amount: decimal(group[:tax]), category_code: "S",
        percent: decimal(group[:rate]), currency_code: "EUR"
      )
    end
  end

  # Überweisung (Code 58 = SEPA-Überweisung) mit IBAN, sonst nur der Hinweis zur Zahlung.
  def payment_instructions
    iban = @invoice.iban.presence
    return unless iban || @invoice.payment_terms.present?

    Zugpferd::Model::PaymentInstructions.new(
      payment_means_code: iban ? "58" : "30", account_id: iban, payment_id: @invoice.invoice_number,
      note: @invoice.payment_terms.presence
    )
  end

  def trade_party(name, email, street, postal_code, city, country)
    party = Zugpferd::Model::TradeParty.new(name: name)
    party.electronic_address = email
    party.electronic_address_scheme = "EM"
    party.postal_address = Zugpferd::Model::PostalAddress.new(
      country_code: country,
      city_name: city,
      postal_zone: postal_code,
      street_name: street
    )
    party
  end

  def build_line(line, index)
    item = Zugpferd::Model::Item.new(name: line.description, description: line.details_text)
    item.tax_category = @invoice.standard_taxed? ? "S" : "E"
    item.tax_percent = decimal(line.tax_rate_percent) if @invoice.standard_taxed?
    price = Zugpferd::Model::Price.new(amount: decimal(line.unit_price))
    Zugpferd::Model::LineItem.new(
      id: index.to_s,
      invoiced_quantity: line.quantity.to_s,
      unit_code: line.unit_code,
      line_extension_amount: decimal(line.line_total),
      item: item,
      price: price
    )
  end

  def add_seller_tax_number(xml)
    document = Nokogiri::XML(xml) { |config| config.strict.nonet }
    namespaces = { "ram" => "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100" }
    seller = document.at_xpath("//ram:SellerTradeParty", namespaces)
    raise "XRechnung fehlt der Rechnungsaussteller" unless seller

    ram_namespace = seller.namespace
    registration = Nokogiri::XML::Node.new("SpecifiedTaxRegistration", document)
    registration.namespace = ram_namespace
    identifier = Nokogiri::XML::Node.new("ID", document)
    identifier.namespace = ram_namespace
    identifier["schemeID"] = "FC"
    identifier.content = @invoice.seller_tax_identifier
    registration.add_child(identifier)
    seller.add_child(registration)
    document.to_xml
  end

  # Die Bestellnummer (BT-13) steht direkt nach der Käuferpartei im Vertragsteil der Rechnung.
  def add_buyer_order_number(xml)
    document = Nokogiri::XML(xml) { |config| config.strict.nonet }
    namespaces = { "ram" => "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100" }
    buyer = document.at_xpath("//ram:ApplicableHeaderTradeAgreement/ram:BuyerTradeParty", namespaces)
    raise "XRechnung fehlt der Rechnungsempfänger" unless buyer

    ram_namespace = buyer.namespace
    reference = Nokogiri::XML::Node.new("BuyerOrderReferencedDocument", document)
    reference.namespace = ram_namespace
    identifier = Nokogiri::XML::Node.new("IssuerAssignedID", document)
    identifier.namespace = ram_namespace
    identifier.content = @invoice.buyer_order_number
    reference.add_child(identifier)
    buyer.add_next_sibling(reference)
    document.to_xml
  end

  # Leistungszeitraum (BT-73, BT-74): steht in der Zahlungsabwicklung hinter den Steuerangaben.
  # Verweis auf die stornierte Rechnung (BT-25).
  def add_cancelled_invoice_reference(xml)
    document = Nokogiri::XML(xml) { |config| config.strict.nonet }
    summation = document.at_xpath("//ram:SpecifiedTradeSettlementHeaderMonetarySummation", "ram" => "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100")
    raise "XRechnung fehlt die Summenangabe" unless summation

    reference = Nokogiri::XML::Node.new("InvoiceReferencedDocument", document)
    reference.namespace = summation.namespace
    id = Nokogiri::XML::Node.new("IssuerAssignedID", document)
    id.namespace = summation.namespace
    id.content = @invoice.cancelled_invoice.invoice_number
    reference.add_child(id)
    summation.add_next_sibling(reference)
    document.to_xml
  end

  def add_billing_period(xml)
    document = Nokogiri::XML(xml) { |config| config.strict.nonet }
    namespaces = {
      "ram" => "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100",
      "udt" => "urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100"
    }
    tax = document.xpath("//ram:ApplicableHeaderTradeSettlement/ram:ApplicableTradeTax", namespaces).last
    raise "XRechnung fehlt die Steuerangabe" unless tax

    period = Nokogiri::XML::Node.new("BillingSpecifiedPeriod", document)
    period.namespace = tax.namespace
    { "StartDateTime" => @invoice.service_on, "EndDateTime" => @invoice.service_until_on }.each do |name, date|
      wrapper = Nokogiri::XML::Node.new(name, document)
      wrapper.namespace = tax.namespace
      value = Nokogiri::XML::Node.new("DateTimeString", document)
      value.namespace = document.root.namespace_definitions.find { |ns| ns.prefix == "udt" }
      value["format"] = "102"
      value.content = date.strftime("%Y%m%d")
      wrapper.add_child(value)
      period.add_child(wrapper)
    end
    tax.add_next_sibling(period)
    document.to_xml
  end

  def decimal(value)
    format("%.2f", value.to_d)
  end
end
