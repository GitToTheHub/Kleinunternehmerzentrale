require "test_helper"

class InvoicesControllerTest < ActionDispatch::IntegrationTest
  test "Rechnungsformular erklärt die Pflicht zur E-Rechnung" do
    get new_invoice_url

    assert_response :success
    assert_select "h1", "Rechnung erstellen"
    assert_select "main", /Seit dem 1\. Januar 2025 müssen auch Kleinunternehmer E-Rechnungen empfangen können/
    assert_select "main", /Als Kleinunternehmer musst du keine E-Rechnung ausstellen/
    assert_select "main", /Rechnungen an Privatpersonen/
    assert_select "main", /Kleinbetragsrechnungen bis 250 Euro/
  end

  test "erstellt eine druckbare Rechnung und eine strukturierte XRechnung" do
    post invoices_url, params: {
      invoice: {
        issued_on: "2026-10-05",
        service_on: "2026-10-04",
        seller_name: "Muster Software",
        seller_street: "Beispielstraße 1",
        seller_postal_code: "20095",
        seller_city: "Hamburg",
        seller_country: "DE",
        seller_email: "ich@example.de",
        seller_tax_identifier: "12/345/67890",
        seller_tax_id_kind: "tax_number",
        buyer_name: "Kundin GmbH",
        buyer_street: "Hauptstraße 2",
        buyer_postal_code: "10115",
        buyer_city: "Berlin",
        buyer_country: "DE",
        buyer_email: "kunde@example.de",
        invoice_lines_attributes: {
          "0" => {
            description: "Softwareentwicklung",
            quantity: "2",
            unit_price: "125.50",
            unit_code: "HUR"
          }
        }
      }
    }

    invoice = Invoice.last
    assert_redirected_to invoice_url(invoice)
    assert_equal "RE-2026-0001", invoice.invoice_number
    assert_equal BigDecimal("251.00"), invoice.total

    get invoice_url(invoice)
    assert_response :success
    assert_select "h1", invoice.invoice_number
    assert_select "main", /Keine Umsatzsteuer ausgewiesen/
    assert_select "a", "XRechnung herunterladen (XML)"

    get xrechnung_invoice_url(invoice)
    assert_response :success
    assert_equal "application/xml", response.media_type
    document = Nokogiri::XML(response.body) { |config| config.strict.nonet }
    namespaces = {
      "ram" => "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100",
      "rsm" => "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100"
    }
    assert_equal "urn:cen.eu:en16931:2017#compliant#urn:xeinkauf.de:kosit:xrechnung_3.0",
      document.at_xpath("//rsm:ExchangedDocumentContext/ram:GuidelineSpecifiedDocumentContextParameter/ram:ID", namespaces).text
    assert_includes response.body, "Steuerbefreiung für Kleinunternehmer nach § 19 UStG"
    tax_identifier = document.at_xpath("//ram:SellerTradeParty/ram:SpecifiedTaxRegistration/ram:ID", namespaces)
    assert_equal "FC", tax_identifier["schemeID"]
    assert_equal "12/345/67890", tax_identifier.text
    assert_equal "251", document.at_xpath("//ram:SpecifiedTradeSettlementLineMonetarySummation/ram:LineTotalAmount", namespaces).text
  end

  test "XRechnung benötigt elektronische Adressen beider Parteien" do
    post invoices_url, params: { invoice: invoice_params_for("Start") }
    invoice = Invoice.create!(
      workspace: Workspace.last,
      issued_on: Date.current,
      service_on: Date.current,
      seller_name: "Muster Software",
      seller_street: "Beispielstraße 1",
      seller_postal_code: "20095",
      seller_city: "Hamburg",
      seller_country: "DE",
      seller_tax_identifier: "12/345/67890",
      seller_tax_id_kind: "tax_number",
      buyer_name: "Kundin GmbH",
      buyer_street: "Hauptstraße 2",
      buyer_postal_code: "10115",
      buyer_city: "Berlin",
      buyer_country: "DE",
      invoice_lines_attributes: [ { description: "Beratung", quantity: 1, unit_price: 90, unit_code: "HUR" } ]
    )

    get xrechnung_invoice_url(invoice)

    assert_redirected_to invoice_url(invoice)
    follow_redirect!
    assert_select ".invoice-email-requirement"
  end

  test "speichert Absender und Kunde und füllt sie bei der nächsten Rechnung vor" do
    2.times do
      post invoices_url, params: { invoice: invoice_params_for("Kundin GmbH") }
      assert_response :redirect
    end

    assert_equal %w[RE-2026-0001 RE-2026-0002], Invoice.where("invoice_number LIKE 'RE-2026-%'").order(:invoice_number).pluck(:invoice_number)
    assert_equal 1, BusinessProfile.count
    assert_equal 1, Customer.where(name: "Kundin GmbH").count

    get new_invoice_url
    assert_select "input#invoice_seller_name[value=?]", "Muster Software"
    assert_select "input#invoice_seller_tax_identifier[value=?]", "12/345/67890"
    assert_select "#customer-select option", /Kundin GmbH, Berlin/
    assert_select ".invoice-number-preview strong", /RE-\d{4}-0003/
  end

  test "schreibt Bestellnummer und Leitweg-ID an die richtigen Stellen der XRechnung" do
    namespaces = {
      "ram" => "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100"
    }
    xpath = ->(doc, path) { doc.at_xpath(path, namespaces)&.text }

    post invoices_url, params: { invoice: invoice_params_for("Amt").merge(buyer_order_number: "PO-12345", buyer_leitweg_id: "991-01234-44") }
    get xrechnung_invoice_url(Invoice.last)
    doc = Nokogiri::XML(response.body)
    assert_equal "991-01234-44", xpath.call(doc, "//ram:ApplicableHeaderTradeAgreement/ram:BuyerReference")
    assert_equal "PO-12345", xpath.call(doc, "//ram:ApplicableHeaderTradeAgreement/ram:BuyerOrderReferencedDocument/ram:IssuerAssignedID")

    post invoices_url, params: { invoice: invoice_params_for("Firma") }
    invoice = Invoice.last
    get xrechnung_invoice_url(invoice)
    doc = Nokogiri::XML(response.body)
    assert_equal invoice.invoice_number, xpath.call(doc, "//ram:ApplicableHeaderTradeAgreement/ram:BuyerReference")
    assert_nil doc.at_xpath("//ram:BuyerOrderReferencedDocument", namespaces)
  end

  test "gibt einen Leistungszeitraum auf der Rechnung und in der XRechnung an" do
    post invoices_url, params: { invoice: invoice_params_for("Kundin GmbH").merge(service_period: "true", service_on: "2026-08-01", service_until_on: "2026-09-30") }
    invoice = Invoice.last
    assert_equal Date.new(2026, 9, 30), invoice.service_until_on

    get invoice_url(invoice)
    assert_select "main", /Leistungszeitraum.*01\.08\.2026 bis 30\.09\.2026/m

    get xrechnung_invoice_url(invoice)
    doc = Nokogiri::XML(response.body)
    ns = { "ram" => "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100", "udt" => "urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100" }
    assert_equal "20260801", doc.at_xpath("//ram:BillingSpecifiedPeriod/ram:StartDateTime/udt:DateTimeString", ns).text
    assert_equal "20260930", doc.at_xpath("//ram:BillingSpecifiedPeriod/ram:EndDateTime/udt:DateTimeString", ns).text
    assert_nil doc.at_xpath("//ram:ActualDeliverySupplyChainEvent", ns)
    order = doc.xpath("//ram:ApplicableHeaderTradeSettlement/*").map(&:name)
    assert_operator order.index("BillingSpecifiedPeriod"), :>, order.index("ApplicableTradeTax")
    assert_operator order.index("BillingSpecifiedPeriod"), :<, order.index("SpecifiedTradeSettlementHeaderMonetarySummation")
  end

  test "lehnt ein Enddatum vor dem Beginn ab und ignoriert es bei einem einzelnen Tag" do
    post invoices_url, params: { invoice: invoice_params_for("X").merge(service_period: "true", service_on: "2026-09-30", service_until_on: "2026-08-01") }
    assert_response :unprocessable_entity

    post invoices_url, params: { invoice: invoice_params_for("X").merge(service_period: "false", service_until_on: "2026-12-01") }
    assert_nil Invoice.last.service_until_on
  end

  test "gibt die Beschreibung der Leistung auf der Rechnung und in der XRechnung aus" do
    params = invoice_params_for("Kundin GmbH")
    params[:invoice_lines_attributes]["0"][:details] = "Umsetzung der Startseite"
    post invoices_url, params: { invoice: params }

    invoice = Invoice.last
    follow_redirect!
    assert_select ".invoice-line-details", /Umsetzung der Startseite/

    get xrechnung_invoice_url(invoice)
    xml = Nokogiri::XML(response.body)
    assert_includes xml.xpath("//*[local-name()='SpecifiedTradeProduct']/*[local-name()='Description']").text, "Umsetzung der Startseite"
  end

  private

  test "merkt sich den Stundensatz einer Stunden-Position und liefert ihn fürs Formular" do
    params = invoice_params_for("Kundin GmbH")
    params[:invoice_lines_attributes]["0"].merge!(unit_code: "HUR", unit_price: "95")
    post invoices_url, params: { invoice: params }
    assert_equal 95, BusinessProfile.last.hourly_rate

    get new_invoice_url
    assert_select "form.invoice-form[data-hourly-rate='95.0']"
    assert_select "#invoice_default_unit_code", false
  end

  test "speichert den Stundensatz je Kunde und liefert ihn im Kundenauswahlfeld" do
    post invoices_url, params: { invoice: invoice_params_for("Kundin GmbH") }
    post invoices_url, params: { invoice: invoice_params_for("Andere AG").tap { |p| p[:invoice_lines_attributes]["0"][:unit_price] = "77" } }

    assert_equal 10, Customer.find_by(name: "Kundin GmbH").hourly_rate
    assert_equal 77, Customer.find_by(name: "Andere AG").hourly_rate

    get new_invoice_url
    assert_select "#customer-select option[data-hourly-rate='77.0']", /Andere AG/
  end

  test "zeigt die Einheit in der Mehrzahl, wenn die Menge nicht 1 ist" do
    params = invoice_params_for("Kundin GmbH")
    params[:invoice_lines_attributes]["0"].merge!(unit_code: "HUR", quantity: "3")
    post invoices_url, params: { invoice: params }
    follow_redirect!
    assert_select "td", /3 Stunden/
    assert_select "title", Invoice.last.invoice_number

    params[:invoice_lines_attributes]["0"][:quantity] = "1"
    post invoices_url, params: { invoice: params }
    follow_redirect!
    assert_select "td", /\A1 Stunde\z/
  end

  test "zeigt Zahlungsangaben auf der Rechnung, merkt sich die IBAN und schreibt sie in die XRechnung" do
    post invoices_url, params: { invoice: invoice_params_for("Kundin GmbH").merge(iban: "de89 3704 0044 0532 0130 00", payment_due_on: "2026-10-19") }
    invoice = Invoice.last
    assert_equal "DE89370400440532013000", invoice.iban
    assert_equal "DE89370400440532013000", BusinessProfile.last.iban

    follow_redirect!
    assert_select ".invoice-payment", /19\.10\.2026/
    assert_select ".invoice-payment", /DE89 3704 0044 0532 0130 00/

    get xrechnung_invoice_url(invoice)
    xml = Nokogiri::XML(response.body)
    assert_equal "DE89370400440532013000", xml.xpath("//*[local-name()='PayeePartyCreditorFinancialAccount']/*[local-name()='IBANID']").text
    assert_equal "20261019", xml.xpath("//*[local-name()='DueDateDateTime']/*").text

    get new_invoice_url
    assert_select "#invoice_iban[value=DE89370400440532013000]"
  end

  test "lehnt eine ungültige IBAN ab" do
    assert_no_difference "Invoice.count" do
      post invoices_url, params: { invoice: invoice_params_for("Kundin GmbH").merge(iban: "DE00 1234") }
    end
    assert_response :unprocessable_entity
  end

  test "speichert die BIC nur für Kunden außerhalb des SEPA-Raums" do
    post invoices_url, params: { invoice: invoice_params_for("Kundin GmbH").merge(bic: "COBADEFFXXX") }
    assert_nil Invoice.last.bic

    params = invoice_params_for("Client Inc").merge(bic: "cobadeffxxx", buyer_country: "US")
    post invoices_url, params: { invoice: params }
    assert_equal "COBADEFFXXX", Invoice.last.bic
    assert_equal "COBADEFFXXX", BusinessProfile.last.bic
  end

  def invoice_params_for(buyer_name)
    {
      issued_on: "2026-10-05", service_on: "2026-10-05",
      seller_name: "Muster Software", seller_street: "Beispielstraße 1", seller_postal_code: "20095",
      seller_city: "Hamburg", seller_country: "DE", seller_email: "ich@example.de",
      seller_tax_identifier: "12/345/67890",
      buyer_name: buyer_name, buyer_street: "Hauptstraße 2", buyer_postal_code: "10115",
      buyer_city: "Berlin", buyer_country: "DE", buyer_email: "kunde@example.de",
      invoice_lines_attributes: { "0" => { description: "Arbeit", quantity: "1", unit_price: "10", unit_code: "HUR" } }
    }
  end

  test "Regelbesteuerung weist Umsatzsteuer aus und erzeugt Kategorie S in der XRechnung" do
    post invoices_url, params: {
      invoice: {
        tax_mode: "standard", issued_on: "2026-10-05", service_on: "2026-10-04",
        seller_name: "Muster Software", seller_street: "Beispielstraße 1", seller_postal_code: "20095",
        seller_city: "Hamburg", seller_country: "DE", seller_email: "ich@example.de",
        seller_tax_identifier: "12/345/67890", seller_tax_id_kind: "tax_number",
        buyer_name: "Kundin GmbH", buyer_street: "Hauptstraße 2", buyer_postal_code: "10115",
        buyer_city: "Berlin", buyer_country: "DE", buyer_email: "kunde@example.de",
        invoice_lines_attributes: {
          "0" => { description: "Beratung", quantity: "2", unit_price: "100", unit_code: "HUR", tax_rate: "19" },
          "1" => { description: "Buch", quantity: "1", unit_price: "10", unit_code: "C62", tax_rate: "7" }
        }
      }
    }

    invoice = Invoice.order(:id).last
    assert_equal 38.7, invoice.tax_total.to_f
    assert_equal 248.7, invoice.total.to_f

    get invoice_url(invoice)
    assert_select "main", /Umsatzsteuer 19 %/
    assert_select "main", /Umsatzsteuer 7 %/
    assert_select ".invoice-tax-note", false

    get xrechnung_invoice_url(invoice)
    assert_match "<ram:CategoryCode>S</ram:CategoryCode>", response.body
    assert_match "<ram:GrandTotalAmount>248.7</ram:GrandTotalAmount>", response.body
    assert_no_match(/CategoryCode>E</, response.body)
  end

  test "Regelbesteuerung verlangt einen Steuersatz je Position" do
    invoice = Invoice.new(tax_mode: "standard")
    invoice.invoice_lines.build(description: "x", quantity: 1, unit_price: 5, unit_code: "C62", tax_rate: 0)
    invoice.valid?
    assert_includes invoice.errors.full_messages, "Bitte wähle für jede Position einen Umsatzsteuersatz"
  end

  test "Formular rendert den Modus am Formular und Kleinunternehmer-Texte als Modus-Inhalt" do
    get new_invoice_url
    assert_select "form.invoice-form[data-tax-mode=small_business]"
    assert_select "[data-show-for=standard] select[name$='[tax_rate]']"
  end

  test "Vorschau zeigt die Rechnung ohne sie zu speichern" do
    assert_no_difference "Invoice.count" do
      post preview_invoices_url, params: { invoice: {
        issued_on: "2026-10-05", service_on: "2026-10-04", seller_name: "Muster Software",
        seller_street: "Beispielstraße 1", seller_postal_code: "20095", seller_city: "Hamburg",
        seller_country: "DE", seller_tax_identifier: "12/345/67890", seller_tax_id_kind: "tax_number",
        buyer_name: "Kundin GmbH", buyer_street: "Hauptstraße 2", buyer_postal_code: "10115",
        buyer_city: "Berlin", buyer_country: "DE",
        invoice_lines_attributes: { "0" => { description: "Beratung", quantity: "1", unit_price: "50", unit_code: "C62" } }
      } }
    end

    assert_response :success
    assert_select ".invoice-preview-banner", /Vorschau/
    assert_select ".print-invoice h1", "RE-2026-0001"
    assert_select ".invoice-actions", false
  end

  test "Vorschau meldet fehlende Angaben" do
    post preview_invoices_url, params: { invoice: { seller_name: "" } }
    assert_response :unprocessable_entity
    assert_select ".form-errors"
  end

  test "IBAN mit falscher Länge oder Prüfsumme wird abgelehnt" do
    invoice = Invoice.new(iban: "DE8937040044053201300")
    invoice.valid?
    assert_includes invoice.errors[:iban].join, "falsche Länge"

    invoice = Invoice.new(iban: "DE89370400440532013001")
    invoice.valid?
    assert_includes invoice.errors[:iban].join, "ungültig"

    invoice = Invoice.new(iban: "de89 3704 0044 0532 0130 00")
    invoice.valid?
    assert_empty invoice.errors[:iban]
  end

  test "Vorschau akzeptiert das CSRF-Token des Formulars" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get new_invoice_url
    token = css_select("form.invoice-form input[name=authenticity_token]").first["value"]

    post preview_invoices_url, params: { authenticity_token: token, invoice: { seller_name: "" } }
    assert_response :unprocessable_entity
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "GET auf die Vorschau führt zurück zum Formular" do
    get "/invoices/preview"
    assert_redirected_to new_invoice_url
  end

  test "Kunde merkt sich Zahlungsfrist und Zahlungshinweis" do
    attrs = { issued_on: "2026-10-05", service_on: "2026-10-05", seller_name: "Muster", seller_street: "Weg 1",
              seller_postal_code: "20095", seller_city: "Hamburg", seller_country: "DE", seller_tax_identifier: "12/345/67890",
              buyer_name: "Frist GmbH", buyer_street: "Str 2", buyer_postal_code: "10115", buyer_city: "Berlin",
              buyer_country: "DE", invoice_lines_attributes: { "0" => { description: "x", quantity: "1", unit_price: "5", unit_code: "C62" } } }

    post invoices_url, params: { invoice: attrs.merge(payment_due_on: "2026-10-19", payment_terms: "2 % Skonto") }
    customer = Customer.find_by!(name: "Frist GmbH")
    assert_equal 14, customer.payment_due_days
    assert_equal "2 % Skonto", customer.payment_terms

    post invoices_url, params: { invoice: attrs }
    assert_nil customer.reload.payment_due_days
  end

  test "Beschreibung erlaubt einfache Formatierung und entfernt Gefährliches" do
    line = InvoiceLine.new(details: '<p>Text <strong>fett</strong></p><script>alert(1)</script><ul><li onclick="x()">Punkt</li></ul>')
    line.valid?
    assert_includes line.details, "<strong>fett</strong>"
    assert_no_match(/script|onclick/, line.details)
    assert_equal "Text fett\n- Punkt", line.details_text

    line = InvoiceLine.new(details: "<p><br></p>")
    line.valid?
    assert_nil line.details

    assert_includes InvoiceLine.new(details: "Zeile 1\nZeile 2").details_html, "<br>"
  end
end
