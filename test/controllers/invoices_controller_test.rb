require "test_helper"
class InvoicesControllerTest < ActionDispatch::IntegrationTest
  test "Vorschau warnt bei kostenlosen Positionen ausserhalb des Rechnungsdokuments" do
    attrs = invoice_params_for("Vorschaukunde")
    attrs[:invoice_lines_attributes]["0"][:unit_price] = "0"
    attrs[:invoice_lines_attributes]["1"] = { description: "Bezahlt", quantity: "1", unit_price: "10", unit_code: "C62" }
    attrs[:invoice_lines_attributes]["2"] = { description: "Kostenlos", quantity: "1", unit_price: "0", unit_code: "C62" }
    patch draft_invoices_url, params: { invoice: attrs }, as: :json
    get draft_preview_invoices_url(draft_id: response.parsed_body.fetch("draft_id"), embedded: "1")
    assert_response :success
    assert_select ".invoice-preview-warning.no-print", /0,00 € in Positionen 1 und 3/
    assert_select ".print-invoice .invoice-preview-warning", count: 0
    post invoices_url, params: { invoice: attrs }
    follow_redirect!
    assert_select ".invoice-preview-warning", count: 0
  end

  test "eingebettete Vorschau zeigt Rechnung und Fehler ohne Seitennavigation" do
    patch draft_invoices_url, params: { invoice: invoice_params_for("Vorschaukunde") }, as: :json
    draft_id = response.parsed_body.fetch("draft_id")
    assert_no_difference "Invoice.count" do
      get draft_preview_invoices_url(draft_id: draft_id, embedded: "1")
      assert_response :success
      assert_select "body.invoice-preview-embedded"
      assert_select ".print-invoice"
      assert_select ".site-header", count: 0
      assert_select "button", text: "Vorschau schließen", count: 0
    end
    draft = InvoiceDraft.find(draft_id)
    draft.update!(data: draft.data.merge("buyer_name" => ""))
    get draft_preview_invoices_url(draft_id: draft_id, embedded: "1")
    assert_response :unprocessable_entity
    assert_select "body.invoice-preview-embedded .form-errors"
    assert_select ".site-header", count: 0
  end

  test "Teilrechnungsauftrag ueberlebt Entwurf Vorschau und Festschreibung mit serverseitiger Anrechnung" do
    attrs = invoice_params_for("Auftragskundin").merge(billing_kind: "advance", title: "", paid: "1", received_on: "2026-10-05")
    post invoices_url, params: { invoice: attrs }
    assert_response :redirect
    advance = Invoice.last
    final_attrs = attrs.merge(billing_kind: "final", billing_root_id: advance.id, customer_id: advance.customer_id, paid: "0",
      invoice_lines_attributes: { "0" => { description: "Gesamter Auftrag", quantity: "1", unit_price: "1.000,00", unit_code: "C62" } },
      deducted_payments: [ { amount: "999.00" } ])
    patch draft_invoices_url, params: { invoice: final_attrs }, as: :json
    assert_response :success
    draft = InvoiceDraft.find(response.parsed_body.fetch("draft_id"))
    assert_equal "final", draft.data.fetch("billing_kind")
    assert_not draft.data.key?("deducted_payments")
    get edit_draft_invoices_url(draft_id: draft.id)
    assert_select "input[type='radio'][name='invoice[billing_kind]'][checked][value='final']"
    assert_select "input#invoice_title:not([required])"
    get draft_preview_invoices_url(draft_id: draft.id)
    assert_response :success
    assert_select ".print-invoice tfoot", /Abzüglich Zahlung zu #{Regexp.escape(advance.invoice_number)}/
    assert_select ".print-invoice tfoot", /Restbetrag/
    post invoices_url, params: { invoice: final_attrs, draft_id: draft.id }
    assert_response :redirect
    final = Invoice.last
    assert_equal advance.payment_entry.amount, final.deducted_total
    assert_equal final.total - advance.total, final.payment_total
    assert draft.reload.completed?
    get new_invoice_url(billing_root_id: advance.id, billing_kind: "progress")
    assert_response :success
    post invoices_url, params: { invoice: final_attrs.merge(billing_kind: "progress") }
    assert_response :unprocessable_entity
    assert_select ".form-errors", /bereits eine Schlussrechnung/
  end

  test "Korrekturvorlage uebernimmt leere Zahlungsfrist statt Standardfrist" do
    post invoices_url, params: { invoice: invoice_params_for("Fristkundin").merge(payment_due_on: "") }
    original = Invoice.last
    post cancel_invoice_url(original)
    follow_redirect!
    assert_select "input[name='invoice[payment_due_on]']" do |fields|
      assert fields.first["value"].blank?
    end
    patch draft_invoices_url, params: { invoice: invoice_params_for("Fristkundin").merge(payment_due_on: "", corrected_invoice_id: original.id) }, as: :json
    draft_id = response.parsed_body.fetch("draft_id")
    get invoice_url(original)
    assert_select "a[href='#{edit_draft_invoices_path(draft_id: draft_id)}']", "Korrekturentwurf weiterbearbeiten"
    assert_select "a[href=?]", new_invoice_path(copy_from: original.id), count: 0
    get edit_draft_invoices_url(draft_id: draft_id)
    assert_select "h1", "Korrekturrechnung erstellen"
    assert_select "button[type='submit'][value='Festschreiben']"
    assert_select ".invoice-status", /Dieser Entwurf korrigiert Rechnung #{Regexp.escape(original.invoice_number)}/
    get invoices_url
    assert_select ".invoice-draft-card", /Korrigiert Rechnung #{Regexp.escape(original.invoice_number)}/
    get edit_draft_invoices_url(draft_id: InvoiceDraft.active.last.id)
    assert_select "input[name='invoice[payment_due_on]']" do |fields|
      assert fields.first["value"].blank?
    end
    InvoiceDraft.find(draft_id).close!(:discarded)
    get invoice_url(original)
    assert_select "a[href=?]", new_invoice_path(copy_from: original.id), text: "Korrigierte Rechnung erstellen"
  end

  test "Uebersicht verbindet Original Storno und korrigierte Rechnung" do
    attrs = invoice_params_for("Korrekturkundin")
    post invoices_url, params: { invoice: attrs }
    original = Invoice.last
    post cancel_invoice_url(original)
    assert_response :redirect
    storno = original.reload.cancellation
    follow_redirect!
    assert_select "input[name='invoice[corrected_invoice_id]'][value='#{original.id}']"
    post invoices_url, params: { invoice: attrs.merge(corrected_invoice_id: original.id) }
    assert_response :redirect
    correction = Invoice.last
    assert_equal original, correction.corrected_invoice
    get invoice_url(correction)
    assert_select ".print-invoice__title .eyebrow", "Korrekturrechnung"
    notice = "Diese Rechnung korrigiert Rechnung #{original.invoice_number} vom #{original.issued_on.strftime('%d.%m.%Y')}."
    assert_select ".print-invoice__correction", notice
    xml = Nokogiri::XML(XrechnungGenerator.new(correction).call)
    assert_equal notice, xml.at_xpath("//*[local-name()='ExchangedDocument']/*[local-name()='IncludedNote']/*[local-name()='Content']").text
    get invoice_url(original)
    assert_select ".invoice-status", /Korrigiert durch #{Regexp.escape(correction.invoice_number)}/
    assert_select ".invoice-status a[href='#{invoice_path(correction)}']", correction.invoice_number
    assert_select "a[href=?]", new_invoice_path(copy_from: original.id), count: 0
    get invoices_url
    assert_select ".invoice-list__item[data-invoice-id='#{original.id}']", /Storniert durch #{Regexp.escape(storno.invoice_number)}/
    assert_select ".invoice-list__item[data-invoice-id='#{original.id}'] .invoice-list__amount--cancelled", count: 1
    assert_select ".invoice-list__item[data-invoice-id='#{storno.id}'] .invoice-list__amount--cancelled", count: 0
    assert_select ".invoice-list__item[data-invoice-id='#{storno.id}']", /Storniert Rechnung #{Regexp.escape(original.invoice_number)}/
    assert_select ".invoice-list__item[data-invoice-id='#{correction.id}']", /Korrigiert Rechnung #{Regexp.escape(original.invoice_number)}/
  end

  test "Barzahlung und bereits bezahlt bleiben getrennt und werden korrekt exportiert" do
    attrs = invoice_params_for("Barkunde").merge(payment_method: "cash", paid: "1", received_on: "2026-10-05", received_account: "business", iban: "", payment_terms: "", payment_due_on: "")
    post invoices_url, params: { invoice: attrs }
    assert_response :redirect
    invoice = Invoice.last
    assert invoice.paid?
    assert_equal Date.new(2026, 10, 5), invoice.payment_entry.paid_on
    assert_equal invoice.total, invoice.payment_entry.amount
    assert_equal "cash", invoice.payment_method
    assert_equal 0, invoice.amount_due
    follow_redirect!
    assert_select ".invoice-payment", /Bereits vollständig bezahlt \(bar\)/
    assert_no_match(/Offener Betrag:/, response.body)
    xml = Nokogiri::XML(XrechnungGenerator.new(invoice).call)
    value = ->(name) { xml.at_xpath("//*[local-name()='#{name}']")&.text }
    assert_equal "10", xml.at_xpath("//*[local-name()='SpecifiedTradeSettlementPaymentMeans']/*[local-name()='TypeCode']").text
    assert_equal "0", value.call("DuePayableAmount")
    assert_equal invoice.total, value.call("TotalPrepaidAmount").to_d
    assert_equal "urn:fdc:peppol.eu:2017:poacc:billing:01:1.0", xml.at_xpath("//*[local-name()='BusinessProcessSpecifiedDocumentContextParameter']/*[local-name()='ID']").text
    assert_equal [ 0.to_d, 0.to_d ], xml.xpath("//*[local-name()='RateApplicablePercent']").map { |node| node.text.to_d }
    invoice.paid = false
    assert_equal invoice.total, invoice.amount_due
    xml = Nokogiri::XML(XrechnungGenerator.new(invoice).call)
    assert_nil xml.at_xpath("//*[local-name()='TotalPrepaidAmount']")
    cancellation = invoice.build_cancellation
    assert_not cancellation.paid?
  end

  test "Stornoaktion ist ein bestaetigter Button im Hinweistext" do
    post invoices_url, params: { invoice: invoice_params_for("Korrekturkunde") }
    follow_redirect!
    assert_select ".invoice-action-hints .invoice-correction-hint", /Fehler auf der Rechnung/
    assert_select ".invoice-correction-hint form[action='#{cancel_invoice_path(Invoice.last)}'][method='post'][data-turbo-confirm] button", "Rechnung stornieren und korrigieren"
    assert_select ".invoice-actions form", count: 0
    assert_select ".invoice-correction-hint form", count: 1
    assert_select ".invoice-cancellation-actions", count: 0
  end

  test "optionaler Rechnungstitel bleibt im Entwurf und erscheint auf Rechnung und Uebersicht" do
    attrs = invoice_params_for("Titelkunde").merge(title: "Website-Betreuung Oktober 2026")
    post preview_invoices_url, params: { invoice: attrs }
    assert_response :redirect
    get invoices_url
    assert_select ".invoice-draft-card", /Website-Betreuung Oktober 2026/
    post invoices_url, params: { invoice: attrs }
    assert_response :redirect
    follow_redirect!
    assert_select ".print-invoice__title h1", Invoice.last.invoice_number
    assert_select ".print-invoice__subject", "Website-Betreuung Oktober 2026"
    xml = Nokogiri::XML(XrechnungGenerator.new(Invoice.last).call)
    assert_equal "Website-Betreuung Oktober 2026", xml.at_xpath("//*[local-name()='ExchangedDocument']/*[local-name()='IncludedNote']/*[local-name()='Content']").text
    get invoices_url
    assert_select ".invoice-list__identity small", "Website-Betreuung Oktober 2026"
    get new_invoice_url(copy_from: Invoice.last.id)
    assert_select "input[name='invoice[title]'][value='Website-Betreuung Oktober 2026']"
  end

  test "Entwurfsuebersicht zeigt Pauschalpreis auch ohne mitgespeicherte Menge" do
    attrs = invoice_params_for("Pauschalkunde")
    attrs[:invoice_lines_attributes].each_value do |line|
      line.delete(:quantity)
      line[:unit_code] = "LS"
      line[:unit_price] = "160"
    end
    post preview_invoices_url, params: { invoice: attrs }
    assert_response :redirect
    get invoices_url
    assert_response :success
    assert_select ".invoice-draft-card", /160,00 €/
  end

  test "EZB Kurs kann ohne Konto abgerufen werden und Fehler bleiben lesbar" do
    rate = { rate: "0.83333333", date: "2026-10-09", source: "EZB-Referenzkurs" }
    service = Object.new
    service.define_singleton_method(:call) { rate }
    original = ExchangeRateLookup.method(:new)
    ExchangeRateLookup.define_singleton_method(:new) { |**| service }
    begin
      assert_no_difference "Invoice.count" do
        get exchange_rate_invoices_url, params: { currency: "USD", issued_on: "2026-10-11" }, as: :json
        assert_response :success
        assert_equal rate[:rate], response.parsed_body.fetch("rate")
      end
    ensure
      ExchangeRateLookup.define_singleton_method(:new, original)
    end
    get exchange_rate_invoices_url, params: { currency: "INVALID", issued_on: "2026-10-11" }, as: :json
    assert_response :unprocessable_entity
    assert response.parsed_body.fetch("error").present?
  end

  test "Fremdwaehrung bleibt in Entwurf Druck XRechnung Kopie und Datenexport erhalten" do
    %w[USD GBP CHF].each do |currency|
      attrs = invoice_params_for("Kunde #{currency}").merge(currency: currency, exchange_rate: "0.92",
        exchange_rate_on: "2026-10-05", exchange_rate_source: "Bankabrechnung")
      post preview_invoices_url, params: { invoice: attrs }
      assert_response :redirect
      draft = InvoiceDraft.last
      assert_equal currency, draft.data.fetch("currency")
      get invoices_url
      assert_select ".invoice-draft-card", /10,00 #{currency}/
      get edit_draft_invoices_url(draft_id: draft.id)
      assert_select "select#invoice_currency option[selected][value=?]", currency
      assert_select "input#invoice_exchange_rate[value='1.08695652']"
      post invoices_url, params: { invoice: attrs, draft_id: draft.id }
      assert_response :redirect
      invoice = Invoice.last
      assert_equal currency, invoice.currency
      get invoice_url(invoice)
      assert_select ".print-invoice", /10,00 #{currency}/
      assert_select ".invoice-euro-conversion", /9,20 €/
      get xrechnung_invoice_url(invoice)
      assert_response :success
      xml = Nokogiri::XML(response.body)
      assert_equal currency, xml.at_xpath("//*[local-name()='InvoiceCurrencyCode']").text
      assert_equal currency, xml.at_xpath("//*[local-name()='TaxTotalAmount']")["currencyID"]
      get new_invoice_url(copy_from: invoice.id)
      assert_select "select#invoice_currency option[selected][value=?]", currency
      assert_select "input#invoice_exchange_rate[value='1.08695652']"
      csv_data = nil
      Zip::File.open_buffer(DataExport.new(invoice.workspace).call) { |zip| csv_data = zip.read("rechnungen.csv") }
      rows = CSV.parse(csv_data.force_encoding("UTF-8").delete_prefix("\uFEFF"), headers: true, col_sep: ";")
      row = rows.find { |entry| entry["Rechnungsnummer"] == invoice.invoice_number }
      assert_equal currency, row["Waehrung"]
      assert_equal "9.2", row["Gesamtbetrag_EUR"]
      assert_equal "Bankabrechnung", row["Kursquelle"]
    end
    get new_invoice_url
    assert_select "select#invoice_currency option[selected][value=EUR]"
  end

  test "Fremdwaehrung ohne Kurs wird auch ohne Browservalidierung abgelehnt" do
    assert_no_difference "Invoice.count" do
      post invoices_url, params: { invoice: invoice_params_for("Ohne Kurs").merge(currency: "USD") }
      assert_response :unprocessable_entity
      assert_select ".form-errors", /Euro-Umrechnungskurs/
    end
  end

  test "Absenderkontakt wird gedruckt exportiert vorausgefuellt und in Kopien erhalten" do
    attrs = invoice_params_for("Kontaktkunde").merge(seller_phone: "+49 40 123456")
    post preview_invoices_url, params: { invoice: attrs }
    assert_response :redirect
    draft = InvoiceDraft.last
    assert_equal attrs[:seller_phone], draft.data.fetch("seller_phone")
    post invoices_url, params: { invoice: attrs, draft_id: draft.id }
    assert_response :redirect
    invoice = Invoice.last
    assert_equal attrs[:seller_phone], invoice.seller_phone
    assert_equal attrs[:seller_phone], invoice.workspace.business_profile.phone
    get invoice_url(invoice)
    assert_select ".print-invoice", /Telefon: \+49 40 123456/
    assert_select ".print-invoice", /ich@example.de/
    xml = Nokogiri::XML(XrechnungGenerator.new(invoice).call)
    assert_equal attrs[:seller_phone], xml.at_xpath("//*[local-name()='SellerTradeParty']//*[local-name()='TelephoneUniversalCommunication']/*[local-name()='CompleteNumber']").text
    get new_invoice_url
    assert_select "input#invoice_seller_phone[value='+49 40 123456']"
    assert_select "input#invoice_seller_email[required]", false
    get new_invoice_url(copy_from: invoice.id)
    assert_select "input#invoice_seller_phone[value='+49 40 123456']"
    assert_equal attrs[:seller_phone], invoice.build_cancellation.seller_phone
  end

  test "Rechnungen und Vorschauen funktionieren ohne Absender E-Mail" do
    attrs = invoice_params_for("Ohne Kontakt").merge(seller_email: "")
    assert_no_difference "Invoice.count" do
      post preview_invoices_url, params: { invoice: attrs }
      assert_response :redirect
    end
    assert_difference "Invoice.count", 1 do
      post invoices_url, params: { invoice: attrs }
      assert_response :redirect
    end
    assert_equal "", Invoice.last.seller_email
    get new_invoice_url
    assert_select "input#invoice_seller_email[required]", false
    assert_select ".invoice-hint__answer", /Nein\. Das gilt dauerhaft/
    assert_select ".invoice-hint__answer", /Die Pflicht, die ab 2027 und 2028 greift, betrifft nur Unternehmen, die Umsatzsteuer ausweisen\./
    assert_select ".invoice-hint__answer", /Eine normale PDF- oder Papierrechnung bleibt für dich erlaubt\./
    assert_select ".e-invoice-note", /Empfangen musst du E-Rechnungen aber können, zum Beispiel per E-Mail\./
    assert_select ".invoice-hint__answer a[href='https://www.gesetze-im-internet.de/ustdv_1980/__34a.html'][target='_blank'][rel='noopener']", "§ 34a UStDV"
    get hilfe_url
    assert_select "#e-rechnung", /E-Rechnungen empfangen können, z\.B\. über ein E-Mail-Postfach/
    assert_select "#e-rechnung", /Internetportal/
  end

  test "Nummernvorschau liefert den Jahreszaehler auch ohne Kundenkuerzel ohne etwas zu speichern" do
    attrs = { issued_on: "2026-10-08", invoice_number_format: "RE-[Jahr]-[Fortlaufendenummer]-[Kundenkürzel]", invoice_number_last: "1000" }
    assert_no_difference [ "Workspace.count", "Invoice.count", "InvoiceDraft.count" ] do
      2.times do
        get next_number_invoices_url, params: attrs, as: :json
        assert_response :unprocessable_entity
        assert_equal "buyer_abbreviation", response.parsed_body.fetch("field")
        assert_equal 1001, response.parsed_body.fetch("sequence")
        assert_not response.parsed_body.key?("invoice_number")
      end
      get next_number_invoices_url, params: attrs.merge(buyer_abbreviation: "MF"), as: :json
      assert_response :success
      assert_equal "RE-2026-1001-MF", response.parsed_body.fetch("invoice_number")
      assert_equal 1001, response.parsed_body.fetch("sequence")
    end
  end

  test "Rechnungsart wird in Vorschau Entwurf und Festschreibung gleich ersetzt" do
    format = "[Rechnungsart]-[Jahr]-[Fortlaufendenummer]"
    assert_no_difference [ "Invoice.count", "Workspace.count" ] do
      get next_number_invoices_url, params: { issued_on: "2026-10-08", invoice_number_format: format, billing_kind: "advance" }, as: :json
      assert_response :success
      assert_equal "ANZ-2026-0001", response.parsed_body.fetch("invoice_number")
    end
    attrs = invoice_params_for("Typkundin").merge(invoice_number_format: format, billing_kind: "advance", title: "App Anpassungen")
    post preview_invoices_url, params: { invoice: attrs }
    assert_response :redirect
    draft = InvoiceDraft.last
    assert_equal format, draft.data.fetch("invoice_number_format")
    get edit_draft_invoices_url(draft_id: draft.id)
    assert_select "input#invoice-number-preview[value='ANZ-2026-0001']"
    post invoices_url, params: { invoice: attrs, draft_id: draft.id }
    assert_response :redirect
    invoice = Invoice.last
    assert_equal "ANZ-2026-0001", invoice.invoice_number
    post cancel_invoice_url(invoice)
    assert_response :redirect
    assert_match /\AST-2026-0002\z/, invoice.reload.cancellation.invoice_number
    assert_equal format, invoice.cancellation.invoice_number_format
    get next_number_invoices_url, params: { issued_on: "2026-10-08", invoice_number_format: format, billing_kind: "unknown" }, as: :json
    assert_response :unprocessable_entity
  end

  test "Umstieg setzt den Zaehlerstand fort und behaelt ihn im Entwurf" do
    attrs = invoice_params_for("Umsteiger").merge(issued_on: "2026-10-08", invoice_number_format: "RE-[Jahr]-[Fortlaufendenummer]", invoice_number_start: "148")
    get next_number_invoices_url, params: attrs, as: :json
    assert_response :success
    assert_equal "RE-2026-0148", response.parsed_body.fetch("invoice_number")
    assert_equal 148, response.parsed_body.fetch("sequence")
    post preview_invoices_url, params: { invoice: attrs }
    assert_response :redirect
    draft = InvoiceDraft.last
    assert_equal "148", draft.data.fetch("invoice_number_start")
    get edit_draft_invoices_url(draft_id: draft.id)
    assert_select "input#invoice_invoice_number_last[value='147']"
    post invoices_url, params: { invoice: attrs, draft_id: draft.id }
    assert_response :redirect
    assert_equal 148, Invoice.last.invoice_number_sequence
    assert_equal "RE-2026-0148", Invoice.last.invoice_number
    post invoices_url, params: { invoice: attrs.except(:invoice_number_start) }
    assert_response :redirect
    assert_equal "RE-2026-0149", Invoice.last.invoice_number
    assert_no_difference "Invoice.count" do
      post invoices_url, params: { invoice: attrs }
      assert_response :unprocessable_entity
    end
  end

  test "ausgestellte Rechnung und XRechnung bleiben nach Aenderungen an Kunde und eigenen Angaben identisch" do
    attrs = invoice_params_for("Urspruenglicher Kunde").merge(iban: "DE89370400440532013000")
    post invoices_url, params: { invoice: attrs }
    assert_response :redirect
    invoice = Invoice.last
    original_attributes = invoice.attributes
    original_lines = invoice.invoice_lines.map(&:attributes)
    original_xml = XrechnungGenerator.new(invoice).call
    get invoice_url(invoice)
    original_print = css_select(".print-invoice").first.to_html

    invoice.customer.update!(name: "Umbenannter Kunde", street: "Neue Kundenadresse 1", email: "neu@example.test")
    invoice.workspace.business_profile.update!(name: "Neue eigene Firma", street: "Neue eigene Adresse 2",
      tax_identifier: "98/765/43210", iban: "DE12500105170648489890", invoice_number_format: "NEU-[Jahr]-[Fortlaufendenummer]")

    assert_equal original_attributes, invoice.reload.attributes
    assert_equal original_lines, invoice.invoice_lines.map(&:attributes)
    assert_equal original_xml, XrechnungGenerator.new(invoice).call
    get invoice_url(invoice)
    assert_equal original_print, css_select(".print-invoice").first.to_html
    assert_raises(ActiveRecord::ReadOnlyRecord) { invoice.update!(buyer_name: "Nachtraeglicher Name") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { invoice.invoice_lines.first.update!(unit_price: 999) }
  end

  test "ausgewaehlter Kunde wird per ID umbenannt und alte Rechnung behaelt ihre Angaben" do
    post invoices_url, params: { invoice: invoice_params_for("Alte Firma") }
    original = Invoice.last
    customer = original.customer
    assert customer
    attrs = invoice_params_for("Neue Firma").merge(customer_id: customer.id, customer_update_mode: "update", buyer_city: "Bremen")
    assert_no_difference "Customer.count" do
      post invoices_url, params: { invoice: attrs }
      assert_response :redirect
    end
    assert_equal customer.id, Invoice.last.customer_id
    assert_equal "Neue Firma", customer.reload.name
    assert_equal "Bremen", customer.city
    assert_equal "Alte Firma", original.reload.buyer_name
    assert_equal "Berlin", original.buyer_city
  end

  test "Rechnungsspezifische Kundenaenderungen bleiben in Entwurf Vorschau und Rechnung ohne Kundenaenderung" do
    post invoices_url, params: { invoice: invoice_params_for("Gespeicherte Firma") }
    customer = Invoice.last.customer
    attrs = invoice_params_for("Abweichender Empfaenger").merge(customer_id: customer.id, customer_update_mode: "invoice_only", buyer_street: "Andere Strasse 9")
    post preview_invoices_url, params: { invoice: attrs }
    assert_response :redirect
    draft = InvoiceDraft.last
    assert_equal customer.id.to_s, draft.data.fetch("customer_id").to_s
    assert_equal "invoice_only", draft.data.fetch("customer_update_mode")
    assert_equal "Gespeicherte Firma", customer.reload.name
    get edit_draft_invoices_url(draft_id: draft.id)
    assert_select "#customer-select option[selected][value=?]", customer.id.to_s
    assert_select "input[name='invoice[customer_update_mode]'][value='invoice_only'][checked]"
    assert_no_difference "Customer.count" do
      post invoices_url, params: { invoice: attrs, draft_id: draft.id }
      assert_response :redirect
    end
    assert_equal customer.id, Invoice.last.customer_id
    assert_equal "Abweichender Empfaenger", Invoice.last.buyer_name
    assert_equal "Gespeicherte Firma", customer.reload.name
    assert_equal "Hauptstraße 2", customer.street
  end

  test "Kundenaenderungen erfordern eine Entscheidung und fremde Kunden sind nicht waehlbar" do
    post invoices_url, params: { invoice: invoice_params_for("Eigene Firma") }
    customer = Invoice.last.customer
    changed = invoice_params_for("Neuer Name").merge(customer_id: customer.id)
    assert_no_difference [ "Invoice.count", "Customer.count" ] do
      post invoices_url, params: { invoice: changed }
      assert_response :unprocessable_entity
      assert_select ".form-errors", /bitte wähle/
      post invoices_url, params: { invoice: changed.merge(customer_id: 0, customer_update_mode: "update") }
      assert_response :unprocessable_entity
      foreign = workspaces(:one).customers.create!(name: "Fremde Firma")
      post invoices_url, params: { invoice: changed.merge(customer_id: foreign.id, customer_update_mode: "update") }
      assert_response :unprocessable_entity
      foreign.destroy!
    end
    assert_equal "Eigene Firma", customer.reload.name
  end

  test "manuell eingegebener neuer Kunde ueberschreibt keinen gleichnamigen Kunden" do
    post invoices_url, params: { invoice: invoice_params_for("Gleicher Name") }
    old_customer = Invoice.last.customer
    assert_difference "Customer.count", 1 do
      post invoices_url, params: { invoice: invoice_params_for("Gleicher Name").merge(buyer_street: "Andere Adresse 9") }
      assert_response :redirect
    end
    assert_not_equal old_customer.id, Invoice.last.customer_id
    assert_equal "Hauptstraße 2", old_customer.reload.street
  end

  test "Standard zaehlt ueber Tage und Kunden hinweg fort" do
    get new_invoice_url
    assert_select "input#invoice-number-format-editor[value=?]", InvoiceNumber::DEFAULT_FORMAT
    assert_select ".invoice-number-template[data-format=?]", "[Kundenkürzel]-[Jahr]-[Monat]-[Tag]-[Tageszähler]" do
      assert_select "strong", "Kundenkürzel, Datum und fortlaufende Nummer pro Tag"
      assert_select "code", "[Kundenkürzel]-[Jahr]-[Monat]-[Tag]-[Tageszähler]"
    end
    numbers = []
    [ [ "2026-10-08", "Kunde A" ], [ "2026-10-08", "Kunde B" ], [ "2026-10-09", "Kunde A" ], [ "2026-10-08", "Kunde C" ] ].each do |date, customer|
      attrs = invoice_params_for(customer).merge(issued_on: date)
      post preview_invoices_url, params: { invoice: attrs }
      assert_response :redirect
      post invoices_url, params: { invoice: attrs }
      assert_response :redirect
      invoice = Invoice.last
      numbers << invoice.invoice_number
      assert_equal InvoiceNumber::DEFAULT_FORMAT, invoice.invoice_number_format
      assert_nil invoice.invoice_number_daily_sequence
      assert_equal invoice.invoice_number.split("-").last.to_i, invoice.invoice_number_sequence
    end
    assert_equal %w[RE-2026-0001 RE-2026-0002 RE-2026-0003 RE-2026-0004], numbers
    assert_equal InvoiceNumber::DEFAULT_FORMAT, Invoice.last.workspace.business_profile.invoice_number_format
  end

  test "eigene Nummernformate bleiben in Entwuerfen erhalten und werden beim Erstellen geprueft" do
    attrs = invoice_params_for("Beispielkunde").merge(issued_on: "2026-10-08", buyer_abbreviation: "beg", invoice_number_format: "[Kundenkürzel]-[Jahr]-[Monat]-[Tag]")
    post preview_invoices_url, params: { invoice: attrs }
    assert_response :redirect
    draft = InvoiceDraft.last
    assert_equal attrs[:invoice_number_format], draft.data.fetch("invoice_number_format")
    get edit_draft_invoices_url(draft_id: draft.id)
    assert_select "input#invoice_buyer_abbreviation[value=beg]"
    post invoices_url, params: { invoice: attrs, draft_id: draft.id }
    assert_response :redirect
    invoice = Invoice.last
    assert_equal "BEG-2026-10-08", invoice.invoice_number
    assert_equal attrs[:invoice_number_format], invoice.workspace.business_profile.invoice_number_format
    assert_equal "BEG", invoice.workspace.customers.find_by!(name: "Beispielkunde").invoice_abbreviation
    assert_includes XrechnungGenerator.new(invoice).call, "BEG-2026-10-08"
    assert_difference "Invoice.count", 1 do
      post invoices_url, params: { invoice: attrs }
      assert_response :redirect
      assert_equal "BEG-2026-10-08-02", Invoice.last.invoice_number
    end
    get next_number_invoices_url, params: { issued_on: "2026-10-08", invoice_number_format: attrs[:invoice_number_format], buyer_abbreviation: "BEG" }, as: :json
    assert_response :success
    assert_equal "BEG-2026-10-08-03", response.parsed_body.fetch("invoice_number")
    get next_number_invoices_url, params: { issued_on: "2026-10-08", invoice_number_format: "" }, as: :json
    assert_response :unprocessable_entity
    attrs[:invoice_number_format] += "-[Fortlaufendenummer]"
    post invoices_url, params: { invoice: attrs }
    assert_response :redirect
    assert_equal "BEG-2026-10-08-0001", Invoice.last.invoice_number
    cancellation = invoice.build_cancellation
    assert cancellation.save, cancellation.errors.full_messages.join(", ")
    assert_match /\AST-\d{4}-\d{4}\z/, cancellation.invoice_number
    assert_equal "BEG-2026-10-08", invoice.reload.invoice_number
    assert_equal attrs[:invoice_number_format], invoice.workspace.business_profile.reload.invoice_number_format
  end

  test "einmaliges Rechnungsnummernformat aendert nicht die gespeicherte Vorgabe" do
    post invoices_url, params: { invoice: invoice_params_for("Erste Rechnung") }
    default_format = Invoice.last.workspace.business_profile.invoice_number_format
    one_time_format = "S-[Jahr]-[Fortlaufendenummer]"
    attrs = invoice_params_for("Einmaliges Format").merge(
      invoice_number_format: one_time_format,
      invoice_number_format_once: "1"
    )

    post preview_invoices_url, params: { invoice: attrs }
    assert_response :see_other
    draft = InvoiceDraft.active.last
    assert_equal "1", draft.data.fetch("invoice_number_format_once")
    get edit_draft_invoices_url(draft_id: draft.id)
    assert_select "input#invoice_invoice_number_format_once[checked]"

    post invoices_url, params: { invoice: attrs, draft_id: draft.id }

    assert_response :redirect
    invoice = Invoice.last
    assert_equal "S-#{Date.current.year}-0002", invoice.invoice_number
    assert_equal one_time_format, invoice.invoice_number_format
    assert_equal default_format, invoice.workspace.business_profile.reload.invoice_number_format
    get new_invoice_url
    assert_select "#invoice-number-format-editor[value=?]", default_format
  end

  test "Rechnungslinks verwenden deutsche Pfade" do
    assert_equal "/rechnungen", invoices_path
    assert_equal "/rechnungen/neu", new_invoice_path
    assert_equal "/rechnungen/entwuerfe/32/bearbeiten", edit_draft_invoices_path(draft_id: 32)
    assert_equal "/rechnungen/entwuerfe/32/vorschau", draft_preview_invoices_path(draft_id: 32)
    assert_equal "/rechnungen/vorschau", preview_invoices_path
    assert_equal "/rechnungen/32/stornieren", cancel_invoice_path(32)
  end

  test "alte Rechnungslinks werden auf deutsche Pfade weitergeleitet" do
    get "/invoices/drafts/32/edit"
    assert_redirected_to "/rechnungen/entwuerfe/32/bearbeiten"
    get "/invoices/32"
    assert_redirected_to "/rechnungen/32"
    get "/invoices/new"
    assert_redirected_to "/rechnungen/neu"
  end

  test "aktuelle Rechnungsnummer richtet sich nach dem ausgewählten Jahr und eigenen Bereich" do
    Invoice.where(id: invoices(:one).id).update_all(invoice_number: "RE-2027-0009")
    assert_no_difference [ "Workspace.count", "Invoice.count", "InvoiceDraft.count" ] do
      get next_number_invoices_url, params: { issued_on: "2027-01-01" }, as: :json
      assert_response :success
      assert_equal "RE-2027-0001", response.parsed_body.fetch("invoice_number")
    end
    post invoices_url, params: { invoice: invoice_params_for("Kundin").merge(issued_on: "2027-01-01") }
    assert_response :redirect
    assert_equal "RE-2027-0001", Invoice.order(:id).last.invoice_number
    get next_number_invoices_url, params: { issued_on: "2027-12-31" }, as: :json
    assert_equal "RE-2027-0002", response.parsed_body.fetch("invoice_number")
    get next_number_invoices_url, params: { issued_on: "2026-10-07" }, as: :json
    assert_equal "RE-2026-0001", response.parsed_body.fetch("invoice_number")
    get next_number_invoices_url, params: { issued_on: "2027-02-31" }, as: :json
    assert_response :unprocessable_entity
  end

  test "Zahlungsfrist wird im Formular geprüft und Serverfehler sind deutsch" do
    get new_invoice_url
    assert_select "[data-date-picker-min-date-field-value='invoice_issued_on'][data-date-picker-min-error-value=?]", "Die Zahlungsfrist darf nicht vor dem Rechnungsdatum liegen."

    attrs = invoice_params_for("Kundin").merge(issued_on: "2026-10-08", payment_due_on: "2026-10-07")
    post preview_invoices_url, params: { invoice: attrs }
    assert_response :unprocessable_entity
    assert_select ".form-errors", /Zahlungsfrist darf nicht vor dem Rechnungsdatum liegen/
    assert_not_includes response.body, "Payment due on"

    assert_no_difference "Invoice.count" do
      post invoices_url, params: { invoice: attrs }
      assert_response :unprocessable_entity
      assert_select ".form-errors", /Zahlungsfrist darf nicht vor dem Rechnungsdatum liegen/
    end
  end

  test "erste Speicherversuche desselben Formulars erzeugen nur einen Entwurf mit numerischer ID" do
    get new_invoice_url
    token = css_select("input[name=form_token]").first["value"]
    assert_select "input[name=draft_id][value]", count: 0
    assert_difference "InvoiceDraft.count", 1 do
      2.times do
        patch draft_invoices_url, params: { form_token: token, invoice: { buyer_name: "Angefangen" } }, as: :json
        assert_response :success
      end
    end
    id = response.parsed_body.fetch("draft_id")
    assert_kind_of Integer, id
    assert_equal edit_draft_invoices_path(draft_id: id), response.parsed_body.fetch("edit_url")
    delete draft_invoices_url, params: { form_token: token }
    assert_response :redirect
    patch draft_invoices_url, params: { form_token: token, invoice: { buyer_name: "Verspätet" } }, as: :json
    assert_response :not_found
    assert InvoiceDraft.find(id).discarded?
  end

  test "Löschen vor dem ersten Speichern verhindert nachträgliches Anlegen" do
    patch draft_invoices_url, params: { invoice: { buyer_name: "Anderer Entwurf" } }, as: :json
    get new_invoice_url
    token = css_select("input[name=form_token]").first["value"]
    delete draft_invoices_url, params: { form_token: token }
    assert_response :redirect
    patch draft_invoices_url, params: { form_token: token, invoice: { buyer_name: "Zu spät" } }, as: :json
    assert_response :not_found
    assert_equal [ "Anderer Entwurf" ], InvoiceDraft.active.map { |draft| draft.data.fetch("buyer_name") }
  end

  test "mehrere Entwürfe bleiben beim Bearbeiten Löschen und Fertigstellen unabhängig" do
    get new_invoice_url
    first_token = css_select("input[name=form_token]").first["value"]
    get new_invoice_url
    second_token = css_select("input[name=form_token]").first["value"]
    assert_not_equal first_token, second_token
    assert_equal 0, InvoiceDraft.active.count

    patch draft_invoices_url, params: { form_token: first_token, invoice: invoice_params_for("Erster Kunde") }, as: :json
    assert_response :success
    first = response.parsed_body.fetch("draft_id")
    assert_kind_of Integer, first
    patch draft_invoices_url, params: { form_token: second_token, invoice: invoice_params_for("Zweiter Kunde") }, as: :json
    assert_response :success
    second = response.parsed_body.fetch("draft_id")
    get invoices_url
    assert_select ".invoice-draft-card", count: 2
    assert_select "a[href=?]", new_invoice_path, text: "Rechnung erstellen"
    get edit_draft_invoices_url(draft_id: first)
    assert_select "#invoice_buyer_name[value='Erster Kunde']"
    assert_select ".invoice-form__actions a[data-action='invoice-draft#back']:not([hidden])", text: "Später"
    assert_select ".invoice-form__actions button[data-action='invoice-draft#discard']", text: "Verwerfen"
    get edit_draft_invoices_url(draft_id: second)
    assert_select "#invoice_buyer_name[value='Zweiter Kunde']"

    delete discard_invoice_draft_invoices_url(draft_id: first), as: :json
    assert_response :no_content
    assert InvoiceDraft.find(first).discarded?
    assert_empty InvoiceDraft.find(first).data
    patch save_invoice_draft_invoices_url(draft_id: first), params: { invoice: invoice_params_for("Verspätetes Speichern") }, as: :json
    assert_response :not_found
    get edit_draft_invoices_url(draft_id: first)
    assert_response :not_found
    assert_equal "Zweiter Kunde", InvoiceDraft.find(second).data.fetch("buyer_name")

    patch draft_invoices_url, params: { invoice: invoice_params_for("Dritter Kunde") }, as: :json
    third = response.parsed_body.fetch("draft_id")
    post invoices_url, params: { draft_id: second, invoice: invoice_params_for("Zweiter Kunde") }
    assert_response :redirect
    assert InvoiceDraft.find(second).completed?
    assert_empty InvoiceDraft.find(second).data
    assert_equal [ third ], InvoiceDraft.active.pluck(:id)
    patch save_invoice_draft_invoices_url(draft_id: second), params: { invoice: invoice_params_for("Verspätet") }, as: :json
    assert_response :not_found
  end

  test "fremde Entwürfe können weder geöffnet überschrieben gelöscht noch abgeschlossen werden" do
    patch draft_invoices_url, params: { invoice: invoice_params_for("Privater Entwurf") }, as: :json
    id = response.parsed_body.fetch("draft_id")
    other = open_session
    other.get edit_draft_invoices_url(draft_id: id)
    other.assert_response :not_found
    other.patch save_invoice_draft_invoices_url(draft_id: id), params: { invoice: invoice_params_for("Fremder Zugriff") }, as: :json
    other.assert_response :not_found
    other.delete discard_invoice_draft_invoices_url(draft_id: id)
    other.assert_response :not_found
    assert_no_difference "Invoice.count" do
      other.post invoices_url, params: { draft_id: id, invoice: invoice_params_for("Fremder Zugriff") }
      other.assert_response :not_found
    end
    assert InvoiceDraft.find(id).active?
    assert_equal "Privater Entwurf", InvoiceDraft.find(id).data.fetch("buyer_name")
  end

  test "Autofill ist für eigene Angaben gruppiert und für Kundendaten ausgeschaltet" do
    get new_invoice_url

    { seller: %w[name email street postal_code city country],
      buyer: %w[name contact_name email street postal_code city country] }.each do |party, fields|
      fields.each do |field|
        autocomplete = party == :seller ? "[autocomplete^='section-seller ']" : "[autocomplete='off']"
        assert_select "#invoice_#{party}_#{field}#{autocomplete}", count: 1
      end
    end
  end

  test "speichert einen unvollständigen Entwurf und stellt ihn im Formular und in der Übersicht wieder her" do
    assert_difference "Workspace.count", 1 do
      patch draft_invoices_url, params: { invoice: {
        seller_name: "Angefangene Firma", buyer_name: "Entwurfskunde",
        invoice_lines_attributes: { "0" => { description: "Erste Leistung", quantity: "2", unit_price: "40", unit_code: "HUR" } }
      } }, as: :json
    end

    assert_response :success
    workspace = Workspace.order(:id).last
    draft = workspace.invoice_drafts.active.first
    assert_equal "Entwurfskunde", draft.data.fetch("buyer_name")
    assert_equal draft.id, response.parsed_body.fetch("draft_id")
    assert draft.updated_at.present?

    get edit_draft_invoices_url(draft_id: draft.id)
    assert_select "input#invoice_seller_name[value=?]", "Angefangene Firma"
    assert_select "input#invoice_buyer_name[value=?]", "Entwurfskunde"
    assert_select "input[name$='[description]'][value=?]", "Erste Leistung"

    get invoices_url
    assert_select ".invoice-draft-card", /Entwurfskunde/
    assert_select "a.invoice-draft-card__link[aria-label=?]", "Entwurf fortsetzen"
  end

  test "eine ausgeschaltete Zahlungsfrist bleibt beim Fortsetzen des Entwurfs ausgeschaltet" do
    get new_invoice_url
    assert_select "#invoice_payment_due_on:not([required])", count: 1

    patch draft_invoices_url, params: { invoice: { buyer_name: "Entwurf", payment_due_on: "2026-10-21" } }, as: :json
    assert_response :success
    workspace = Workspace.order(:id).last
    id = response.parsed_body.fetch("draft_id")
    get edit_draft_invoices_url(draft_id: id)
    assert_select "#invoice_payment_due_on:not([required])", count: 1
    assert_select "#invoice_payment_due_on[value='2026-10-21']"

    # An empty optional date is stored without a deadline.
    patch save_invoice_draft_invoices_url(draft_id: id), params: { invoice: { buyer_name: "Entwurf" } }, as: :json
    assert_response :success
    assert_nil workspace.invoice_drafts.find(id).data.fetch("payment_due_on")
    get invoices_url
    get edit_draft_invoices_url(draft_id: id)
    assert_select "#due_date_enabled", count: 0
    assert_select "#invoice_payment_due_on[value]", count: 0

    patch save_invoice_draft_invoices_url(draft_id: id), params: { invoice: { buyer_name: "Entwurf", payment_due_on: "2026-10-28" } }, as: :json
    get edit_draft_invoices_url(draft_id: id)
    assert_select "#invoice_payment_due_on:not([required])", count: 1
    assert_select "#invoice_payment_due_on[value='2026-10-28']"
  end

  test "bestehende Entwürfe ohne Zahlungsdatum erhalten keine automatische Zahlungsfrist" do
    patch draft_invoices_url, params: { invoice: { buyer_name: "Alter Entwurf" } }, as: :json
    workspace = Workspace.order(:id).last
    draft = workspace.invoice_drafts.active.first
    draft.update!(data: { "buyer_name" => "Alter Entwurf" })

    get edit_draft_invoices_url(draft_id: draft.id)

    assert_select "#invoice_buyer_name[value='Alter Entwurf']"
    assert_select "#due_date_enabled", count: 0
    assert_select "#invoice_payment_due_on[value]", count: 0
  end

  test "Löschen verwirft den Entwurf" do
    patch draft_invoices_url, params: { invoice: { buyer_name: "Wird verworfen" } }, as: :json
    workspace = Workspace.order(:id).last

    delete discard_invoice_draft_invoices_url(draft_id: workspace.invoice_drafts.active.first.id)

    assert_redirected_to invoices_url
    assert_empty workspace.invoice_drafts.active
    follow_redirect!
    assert_select ".invoice-draft-card", count: 0
  end

  test "eine erstellte Rechnung entfernt den zugehörigen Entwurf" do
    patch draft_invoices_url, params: { invoice: { buyer_name: "Entwurf" } }, as: :json
    workspace = Workspace.order(:id).last

    post invoices_url, params: { draft_id: workspace.invoice_drafts.active.first.id, invoice: invoice_params_for("Fertige Rechnung") }

    assert_response :redirect
    assert_empty workspace.invoice_drafts.active
  end

  test "Rechnungsformular bündelt die Angaben in vier Schritten" do
    get new_invoice_url

    assert_select "form[data-controller~='invoice-wizard']" do
      assert_select "section.invoice-step[data-invoice-wizard-target='step']", count: 4
      assert_select ".invoice-step__heading h2", count: 4
      assert_select "details.invoice-step", count: 0
      assert_select "[data-invoice-wizard-target='step'][aria-labelledby='invoice-step-seller']" do
        assert_select "details.invoice-seller-details[open]"
        assert_select "h3", "Adresse"
        assert_select "h3", "Steuerangaben"
        assert_select "input[name='invoice[seller_name]']"
        assert_select ".tax-mode", count: 0
        assert_select ".invoice-hint", count: 0
      end
      assert_select ".tax-mode", count: 0
      assert_select "form > section.e-invoice-note", count: 1
      assert_select "[data-invoice-wizard-target='step'][aria-labelledby='invoice-step-buyer'] input[name='invoice[buyer_name]']"
      assert_select "[data-invoice-wizard-target='step'][aria-labelledby='invoice-step-dates'] input[name='invoice[issued_on]']"
      assert_select "[data-invoice-wizard-target='step'][aria-labelledby='invoice-step-lines']" do
        assert_select "[data-controller='invoice-lines']"
      end
      assert_select ".invoice-form__actions button[type='submit'][value='Festschreiben']"
      assert_select ".invoice-form__actions button[type='submit'][value='Vorschau']"
      assert_select ".invoice-form__actions a[href=?][hidden][data-action='invoice-draft#back']", invoices_path, text: "Später"
      assert_select ".invoice-form__actions button[type=button][data-action='invoice-draft#discard']", text: "Abbrechen"
      assert_select ".invoice-form__actions [data-turbo-method='delete']", count: 0
      assert_select "section.e-invoice-note h2", "Musst du eine E-Rechnung ausstellen?"
      assert_select "details.invoice-hint", false
    end
  end

  test "gespeicherte eigene Angaben sind standardmaessig eingeklappt" do
    post invoices_url, params: { invoice: invoice_params_for("Profilkundin") }
    get new_invoice_url

    assert_select "details.invoice-seller-details:not([open])"
    assert_select "details.invoice-seller-details > summary" do
      assert_select ".invoice-seller-summary strong", "Muster Software"
      assert_select ".invoice-seller-summary", /Beispielstraße 1, 20095 Hamburg, Deutschland/
      assert_select ".invoice-seller-summary", /12\/345\/67890/
      assert_select ".invoice-seller-summary", /ich@example\.de/
      assert_select ".invoice-seller-summary__action svg"
    end
  end

  test "Rechnungsformular erklärt die Pflicht zur E-Rechnung" do
    get new_invoice_url

    assert_response :success
    assert_select "h1", "Rechnung erstellen"
    assert_select ".invoice-hint__answer", /Nein\. Das gilt dauerhaft/
    assert_select ".e-invoice-note", /Empfangen musst du E-Rechnungen aber können, zum Beispiel per E-Mail\./
    assert_select ".e-invoice-note a[href=?][target='_blank'][rel='noopener']", hilfe_path(anchor: "e-rechnung"), text: "Weiteres zur E-Rechnung in der Hilfe"

    get hilfe_url
    assert_select "article#e-rechnung", /Seit dem 1\. Januar 2025 müssen auch Kleinunternehmer E-Rechnungen empfangen können/
    assert_select "article#e-rechnung", /Nein\. Das gilt dauerhaft/
    get new_invoice_url
    assert_select ".invoice-hint details", false
    assert_select "label", "Webadresse"
    assert_select "#customer-imprint-lookup[popover]" do
      assert_select "h3", "Kundendaten aus Impressum"
      assert_select "button", "Daten ermitteln"
    end
    assert_select "main", /Du kannst auch direkt den Link zum Impressum hier einfügen/
    assert_select "label", "Inhaber/in oder Ansprechperson (optional)"
    assert_select "input[name='invoice[buyer_contact_name]'][aria-describedby='buyer-contact-name-help']"
    assert_select "#buyer-contact-name-help", /Genügt der Firmenname, lass das Feld leer/
    get hilfe_url
    assert_response :success
    assert_select "article#e-rechnung" do
      assert_select "h2", "Was ist eine E-Rechnung, XRechnung oder ZUGFeRD, und wann gilt die Pflicht?"
      assert_select "h3", "XRechnung oder ZUGFeRD?"
      assert_select "li", /Rechnungen an Privatpersonen/
      assert_select "li", /Kleinbetragsrechnungen bis 250 Euro/
    end
  end

  test "Impressumsabruf gibt verständliche Fehlermeldungen zurück" do
    post lookup_customer_imprint_invoices_url, params: { domain: "127.0.0.1" }, as: :json

    assert_response :unprocessable_entity
    assert_match(/öffentlich erreichbares Ziel/, response.parsed_body.fetch("error"))
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
        buyer_contact_name: "Mira Mustermann",
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
    assert_equal "Mira Mustermann", invoice.buyer_contact_name

    get invoice_url(invoice)
    assert_response :success
    assert_select "h1", invoice.invoice_number
    assert_select "main", /Keine Umsatzsteuer ausgewiesen/
    assert_select "a[data-turbo='false'][download=?]", "#{invoice.invoice_number}.xml", text: "XRechnung herunterladen (XML)"
    assert_select ".print-invoice__recipient", /Mira Mustermann/

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
    assert_equal "Mira Mustermann", document.at_xpath("//ram:BuyerTradeParty/ram:DefinedTradeContact/ram:PersonName", namespaces).text
    assert_equal "251", document.at_xpath("//ram:SpecifiedTradeSettlementLineMonetarySummation/ram:LineTotalAmount", namespaces).text
  end

  test "XRechnung benötigt elektronische Adressen beider Parteien" do
    post invoices_url, params: { invoice: invoice_params_for("Start") }
    invoice = Invoice.create!(
      workspace: Workspace.last,
      issued_on: Date.current,
      service_on: Date.current,
      seller_name: "Muster Software",
      seller_email: "muster@example.test",
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
      post invoices_url, params: { invoice: invoice_params_for("Kundin GmbH").merge(buyer_contact_name: "Mira Mustermann") }
      assert_response :redirect
    end

    assert_equal %w[RE-2026-0001 RE-2026-0002], Invoice.where("invoice_number LIKE 'RE-2026-%'").order(:invoice_number).pluck(:invoice_number)
    assert_equal 1, BusinessProfile.count
    assert_equal 1, Customer.where(name: "Kundin GmbH").count
    assert_equal "Mira Mustermann", Customer.find_by!(name: "Kundin GmbH").contact_name

    get new_invoice_url
    assert_select "input#invoice_seller_name[value=?]", "Muster Software"
    assert_select "input#invoice_seller_tax_identifier[value=?]", "12/345/67890"
    assert_select "#customer-select option", /Kundin GmbH, Berlin/
    customer_values = JSON.parse(css_select("#customer-select option[data-values]").first["data-values"])
    assert_equal "Mira Mustermann", customer_values.fetch("buyer_contact_name")
    assert_select "#invoice-number-preview[readonly][value]" do |fields|
      assert_equal "RE-#{Date.current.year}-0003", fields.first["value"]
    end
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

  test "speichert den expliziten Stundensatz unabhaengig vom Positionspreis" do
    params = invoice_params_for("Kundin GmbH")
    params[:seller_hourly_rate] = "95,50"
    params[:invoice_lines_attributes]["0"].merge!(unit_code: "HUR", unit_price: "120")
    post invoices_url, params: { invoice: params }
    assert_equal BigDecimal("95.50"), BusinessProfile.last.hourly_rate

    get new_invoice_url
    assert_select "form.invoice-form[data-hourly-rate='95.5']"
    assert_select "#invoice_default_unit_code", false
  end

  test "leerer Stundensatz entfernt die globale Vorgabe und Positionspreise setzen sie nicht neu" do
    params = invoice_params_for("Kundin GmbH").merge(seller_hourly_rate: "80")
    post invoices_url, params: { invoice: params }
    assert_equal 80, BusinessProfile.last.hourly_rate
    post invoices_url, params: { invoice: invoice_params_for("Andere AG").merge(seller_hourly_rate: "") }
    assert_nil BusinessProfile.last.hourly_rate
    post invoices_url, params: { invoice: invoice_params_for("Dritte AG") }
    assert_nil BusinessProfile.last.hourly_rate
  end

  test "individueller Stundensatz wird explizit gespeichert und kann entfernt werden" do
    post invoices_url, params: { invoice: invoice_params_for("Kundin GmbH").merge(seller_hourly_rate: "80", buyer_hourly_rate: "95,50") }
    assert_response :redirect
    customer = Customer.find_by!(name: "Kundin GmbH")
    assert_equal BigDecimal("95.50"), customer.hourly_rate
    assert_equal 80, customer.workspace.business_profile.hourly_rate
    post invoices_url, params: { invoice: invoice_params_for("Kundin GmbH").merge(customer_id: customer.id, customer_update_mode: "update", buyer_hourly_rate: "") }
    assert_response :redirect
    assert_nil customer.reload.hourly_rate
    assert_equal 80, customer.workspace.business_profile.hourly_rate
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

  test "Rechnung ohne Zahlbetrag zeigt keinen Zahlungsbereich" do
    params = invoice_params_for("Nullbetrag GmbH").merge(
      iban: "DE89370400440532013000", payment_due_on: "2026-10-19", payment_terms: "Bitte überweisen")
    params[:invoice_lines_attributes]["0"][:unit_price] = "0"
    post invoices_url, params: { invoice: params }
    assert_response :redirect
    follow_redirect!
    assert_select ".print-invoice tfoot", /0,00/
    assert_select ".invoice-payment", count: 0
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

  test "Regelbesteuerung kann nicht ueber Formularparameter aktiviert werden" do
    attributes = invoice_params_for("Kundin GmbH").merge(tax_mode: "standard")
    attributes[:invoice_lines_attributes]["0"][:tax_rate] = "19"
    assert_no_difference [ "Invoice.count", "InvoiceDraft.count" ] do
      [ [ :post, invoices_url ], [ :post, preview_invoices_url ], [ :patch, draft_invoices_url ] ].each do |method, url|
        public_send method, url, params: { invoice: attributes }
        assert_response :unprocessable_entity
        assert_includes response.parsed_body.fetch("error"), "Kleinunternehmerregelung"
      end
    end
  end

  test "uebermittelte Umsatzsteuersaetze erzeugen keine Umsatzsteuer bei neuen Rechnungen" do
    attributes = invoice_params_for("Kleinunternehmerkunde")
    attributes[:invoice_lines_attributes]["0"][:tax_rate] = "19"
    post invoices_url, params: { invoice: attributes }
    assert_response :redirect
    invoice = Invoice.order(:id).last
    assert_equal "small_business", invoice.tax_mode
    assert_equal 0, invoice.invoice_lines.sole.tax_rate
    assert_equal 0, invoice.tax_total
    get xrechnung_invoice_url(invoice)
    assert_response :success
    assert_match "<ram:CategoryCode>E</ram:CategoryCode>", response.body
    assert_no_match(/CategoryCode>S</, response.body)
  end

  test "aeltere Regelbesteuerungsrechnungen bleiben mit ihren Steuerbetraegen lesbar" do
    post invoices_url, params: { invoice: invoice_params_for("Kundin GmbH") }
    workspace = Invoice.order(:id).last.workspace
    attributes = invoice_params_for("Historischer Kunde").merge(tax_mode: "standard")
    attributes[:invoice_lines_attributes]["0"][:tax_rate] = "19"
    invoice = workspace.invoices.create!(attributes)
    get invoice_url(invoice)
    assert_response :success
    assert_select "main", /Umsatzsteuer 19 %/
    assert_select ".invoice-tax-note", false
    get xrechnung_invoice_url(invoice)
    assert_response :success
    assert_match "<ram:CategoryCode>S</ram:CategoryCode>", response.body
    assert_equal BigDecimal("11.90"), invoice.reload.total
    get new_invoice_url
    assert_response :success
    assert_select "main", /Kleinunternehmerregelung ohne Umsatzsteuerausweis/
    post invoices_url, params: { invoice: invoice_params_for("Neuer Kleinunternehmerkunde") }
    assert_response :redirect
    assert_equal "small_business", Invoice.order(:id).last.tax_mode
    assert_equal 0, Invoice.order(:id).last.tax_total
    assert_equal BigDecimal("11.90"), invoice.reload.total
  end

  test "aeltere Regelbesteuerungsentwuerfe werden nicht stillschweigend umgerechnet" do
    patch draft_invoices_url, params: { invoice: invoice_params_for("Entwurfskunde") }
    draft = InvoiceDraft.active.order(:id).last
    data = draft.data.merge("tax_mode" => "standard")
    draft.update!(data: data)
    get edit_draft_invoices_url(draft_id: draft.id)
    assert_redirected_to invoices_url
    patch save_invoice_draft_invoices_url(draft_id: draft.id), params: { invoice: invoice_params_for("Geaenderter Kunde") }
    assert_response :unprocessable_entity
    assert_equal data, draft.reload.data
    post invoices_url, params: { draft_id: draft.id, invoice: invoice_params_for("Geaenderter Kunde") }
    assert_response :unprocessable_entity
    assert draft.reload.active?
    assert_equal data, draft.data
  end

  test "Regelbesteuerung verlangt einen Steuersatz je Position" do
    invoice = Invoice.new(tax_mode: "standard")
    invoice.invoice_lines.build(description: "x", quantity: 1, unit_price: 5, unit_code: "C62", tax_rate: 0)
    invoice.valid?
    assert_includes invoice.errors.full_messages, "Bitte wähle für jede Position einen Umsatzsteuersatz"
  end

  test "Formular bietet ausschliesslich Kleinunternehmerrechnungen an" do
    get new_invoice_url
    assert_select "form.invoice-form"
    assert_select "input[name='invoice[tax_mode]']", false
    assert_select "select[name$='[tax_rate]']", false
    assert_select "main", /Kleinunternehmerregelung ohne Umsatzsteuerausweis/
    assert_select "[data-show-for=standard]", false
  end

  test "Vorschau speichert den Entwurf und zeigt ihn unter einer neu ladbaren Adresse ohne eine Rechnung zu erstellen" do
    assert_no_difference "Invoice.count" do
      post preview_invoices_url, params: { invoice: {
        issued_on: "2026-10-05", service_on: "2026-10-04", seller_name: "Muster Software", seller_email: "muster@example.test",
        seller_street: "Beispielstraße 1", seller_postal_code: "20095", seller_city: "Hamburg",
        seller_country: "DE", seller_tax_identifier: "12/345/67890", seller_tax_id_kind: "tax_number",
        buyer_name: "Kundin GmbH", buyer_street: "Hauptstraße 2", buyer_postal_code: "10115",
        buyer_city: "Berlin", buyer_country: "DE",
        invoice_lines_attributes: { "0" => { description: "Beratung", quantity: "1", unit_price: "50", unit_code: "C62" } }
      } }
    end

    workspace = Workspace.order(:id).last
    preview_path = draft_preview_invoices_path(draft_id: workspace.invoice_drafts.active.first.id)
    assert_response :see_other
    assert_redirected_to preview_path
    assert_equal "Kundin GmbH", workspace.invoice_drafts.active.first.data.fetch("buyer_name")
    follow_redirect!
    assert_response :success
    assert_select ".invoice-preview-banner", /Vorschau/
    assert_select "[data-controller='invoice-pagination']" do
      assert_select "article[data-invoice-pagination-target='source']"
      assert_select "[data-invoice-pagination-target='pages']"
    end
    assert_select ".print-invoice h1", "RE-2026-0001"
    assert_select ".invoice-actions", false

    get preview_path
    assert_response :success
    assert_select ".print-invoice__recipient", /Kundin GmbH/
  end

  test "die Entwurfsvorschau behält ihre Kennung beim Speichern und zeigt den aktuellen Stand" do
    patch draft_invoices_url, params: { invoice: invoice_params_for("Erster Stand") }, as: :json
    preview_path = response.parsed_body.fetch("preview_url")
    id = response.parsed_body.fetch("draft_id")

    post preview_invoices_url, params: { draft_id: id, invoice: invoice_params_for("Aktueller Stand") }
    assert_redirected_to preview_path
    assert_equal id, Workspace.order(:id).last.invoice_drafts.active.first.id
    follow_redirect!
    assert_select ".print-invoice__recipient", /Aktueller Stand/

    patch save_invoice_draft_invoices_url(draft_id: id), params: { invoice: invoice_params_for("Später geändert") }, as: :json
    assert_equal id, response.parsed_body.fetch("draft_id")
    get preview_path
    assert_select ".print-invoice__recipient", /Später geändert/
  end

  test "eine Entwurfsvorschau ist nur im eigenen Bereich erreichbar" do
    patch draft_invoices_url, params: { invoice: invoice_params_for("Eigener Entwurf") }, as: :json
    preview_path = response.parsed_body.fetch("preview_url")

    other = open_session
    other.get preview_path
    other.assert_response :not_found
    other.patch draft_invoices_url, params: { invoice: invoice_params_for("Fremder Entwurf") }, as: :json
    other.get preview_path
    other.assert_response :not_found

    get preview_path
    assert_response :success
    assert_select ".print-invoice__recipient", /Eigener Entwurf/
  end

  test "die alte Vorschauadresse eines gelöschten Entwurfs zeigt nicht einen neuen Entwurf" do
    patch draft_invoices_url, params: { invoice: invoice_params_for("Alter Entwurf") }, as: :json
    old_path = response.parsed_body.fetch("preview_url")
    delete discard_invoice_draft_invoices_url(draft_id: response.parsed_body.fetch("draft_id"))
    get old_path
    assert_response :not_found

    patch draft_invoices_url, params: { invoice: invoice_params_for("Neuer Entwurf") }, as: :json
    new_path = response.parsed_body.fetch("preview_url")
    assert_not_equal old_path, new_path
    get old_path
    assert_response :not_found
    get new_path
    assert_response :success
  end

  test "nach dem Erstellen der Rechnung ist die Entwurfsvorschau nicht mehr verfügbar" do
    patch draft_invoices_url, params: { invoice: invoice_params_for("Entwurf") }, as: :json
    preview_path = response.parsed_body.fetch("preview_url")
    post invoices_url, params: { draft_id: response.parsed_body.fetch("draft_id"), invoice: invoice_params_for("Fertige Rechnung") }
    assert_response :redirect
    get preview_path
    assert_response :not_found
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
    get preview_invoices_path
    assert_redirected_to new_invoice_url
  end

  test "Kunde merkt sich Zahlungsfrist und Zahlungshinweis" do
    attrs = { issued_on: "2026-10-05", service_on: "2026-10-05", seller_name: "Muster", seller_email: "muster@example.test", seller_street: "Weg 1",
              seller_postal_code: "20095", seller_city: "Hamburg", seller_country: "DE", seller_tax_identifier: "12/345/67890",
              buyer_name: "Frist GmbH", buyer_street: "Str 2", buyer_postal_code: "10115", buyer_city: "Berlin",
              buyer_country: "DE", invoice_lines_attributes: { "0" => { description: "x", quantity: "1", unit_price: "5", unit_code: "C62" } } }

    post invoices_url, params: { invoice: attrs.merge(payment_due_on: "2026-10-19", payment_terms: "2 % Skonto") }
    customer = Customer.find_by!(name: "Frist GmbH")
    assert_equal 14, customer.payment_due_days
    assert_equal "2 % Skonto", customer.payment_terms

    post invoices_url, params: { invoice: attrs.merge(customer_id: customer.id, customer_update_mode: "update") }
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

    line = InvoiceLine.new(details: "Einleitung\n- Erster Punkt\n- Zweiter Punkt")
    assert_match(/<ul>\s*<li>Erster Punkt<\/li>\s*<li>Zweiter Punkt<\/li>\s*<\/ul>/, line.details_html)
    assert_includes line.details_html, "<p>Einleitung</p>"

    line = InvoiceLine.new(details: "<div>- Erster Punkt</div><div>- Zweiter Punkt</div>")
    assert_match(/<ul>\s*<li>Erster Punkt<\/li>\s*<li>Zweiter Punkt<\/li>\s*<\/ul>/, line.details_html)
    assert_no_match(/<li>\s*[-–—]/, line.details_html)
  end
end
