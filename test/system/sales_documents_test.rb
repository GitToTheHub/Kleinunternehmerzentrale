require "application_system_test_case"

class SalesDocumentsTest < ApplicationSystemTestCase
  test "direkte Anzahlung berechnet die Haelfte und Schlussrechnung zieht die Zahlung ab" do
    visit new_invoice_path
    fill_parties
    assert_selector "[data-order-billing-target=scopeHint]", text: "Beschreibe jede Leistung oder jeden Artikel"
    choose "Anzahlungsrechnung"
    assert_selector "h1", text: "Anzahlungsrechnung erstellen"
    assert_no_selector "input[type=checkbox][name='invoice[order_based]']"
    assert_no_selector "[data-order-billing-target=scopeHint]"
    assert page.evaluate_script("Boolean(document.querySelector('[data-order-billing-target=panel]').compareDocumentPosition(document.querySelector('[data-invoice-lines-target=list]')) & Node.DOCUMENT_POSITION_FOLLOWING)")
    fill_in "invoice_invoice_lines_attributes_0_description", with: "Anpassungen am Teilnehmermanagement"
    select "Pauschal", from: "invoice_invoice_lines_attributes_0_unit_code"
    fill_in "invoice_invoice_lines_attributes_0_unit_price", with: "800,00"
    assert_selector "[data-order-billing-target=total]", text: "800,00"
    assert_selector "[data-order-billing-target=requested]", text: "400,00"
    assert_selector "[data-order-billing-target=remaining]", text: "400,00"
    assert_no_difference "SalesDocument.count" do
      click_button "Vorschau"
      within_frame("invoice-preview-frame") do
        assert_no_selector ".invoice-order-summary"
        assert_selector ".invoice-table tbody", text: "Anpassungen am Teilnehmermanagement"
        assert_no_selector ".invoice-table tbody", text: "Anzahlungsrechnung auf den Gesamtauftrag"
        assert_selector ".invoice-table tfoot", text: "Gesamtpreis des Auftrags"
        assert_selector ".invoice-table tfoot", text: "Anzahlung (50 %)"
        assert_selector ".invoice-pages .invoice-table tfoot", text: "400,00"
      end
      click_button "Vorschau schließen"
    end
    click_button "Festschreiben"
    assert_current_path %r{\A/rechnungen/\d+\z}
    advance = Invoice.order(:id).last
    assert_equal 400.to_d, advance.total
    assert_equal 800.to_d, advance.sales_document.total_amount
    visit invoices_path
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    within("#invoice_#{advance.id}") do
      assert_selector ".invoice-list__amount", text: /400,00.*von 800,00/m
    end
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    visit invoice_path(advance)
    within("section[aria-label='Zahlungsstatus']") { click_link "Als bezahlt markieren" }
    assert_selector "dialog[open]"
    fill_in "Datum des Zahlungseingangs", with: Date.current.strftime("%d.%m.%Y")
    assert_selector "#payment-dialog-title", text: "Rechnung als bezahlt markieren"
    assert_text "Betrag: 400,00"
    click_button "Rechnung als bezahlt markieren"
    assert_no_selector "dialog[open]"
    visit invoice_path(advance)
    click_link "Weitere Anzahlung erstellen"
    assert_selector "[data-order-billing-target=prior]", text: "400,00"
    assert_selector "[data-order-billing-target=priorPaid]", text: "400,00"
    assert_selector "[data-order-billing-target=requested]", text: "400,00"
    assert_selector "[data-order-billing-target=remaining]", text: "0,00"
    click_button "Vorschau"
    within_frame("invoice-preview-frame") do
      assert_selector ".invoice-table tfoot", text: "Bereits abgerechnet mit #{advance.invoice_number}"
      assert_selector ".invoice-table tfoot", text: "Davon bereits bezahlt (Stand dieser Rechnung)"
      assert_selector ".invoice-table tfoot tr", text: /Nach dieser Rechnung noch nicht abgerechnet.*0,00/m
      assert_selector ".invoice-table tfoot tr", text: /Mit dieser Rechnung zu zahlen.*400,00/m
    end
    click_button "Vorschau schließen"
    visit invoice_path(advance)
    click_link "Schlussrechnung erstellen"
    assert_checked_field "invoice_billing_kind_final"
    assert_text "Anpassungen am Teilnehmermanagement"
    click_button "Festschreiben"
    assert_current_path %r{\A/rechnungen/\d+\z}
    final = Invoice.order(:id).last
    assert_equal "final", final.billing_kind
    assert_equal 800.to_d, final.total
    assert_equal 400.to_d, final.deducted_total
    assert_equal 400.to_d, final.payment_total
    assert_equal advance.sales_document_id, final.sales_document_id
  end

  test "Angebot wird als Auftrag uebernommen und ohne Pflichtanzahlung abgerechnet" do
    visit new_sales_document_path
    fill_parties
    fill_in "invoice_invoice_lines_attributes_0_description", with: "Vereinbarte Anpassungen"
    select "Pauschal", from: "invoice_invoice_lines_attributes_0_unit_code"
    fill_in "invoice_invoice_lines_attributes_0_unit_price", with: "800,00"
    click_button "Angebot speichern"
    assert_selector "h1", text: /Angebot AN-/
    assert_selector ".invoice-pages:not(.invoice-pages--rendering) .pagedjs_page"
    click_button "Als Auftrag übernehmen"
    assert_selector "h1", text: /Auftrag AU-/
    order = SalesDocument.order(:id).last
    assert order.source_offer_id
    click_link "Rechnung erstellen"
    assert_checked_field "invoice_billing_kind_regular"
    assert_text "Vereinbarte Anpassungen"
    click_button "Festschreiben"
    assert_current_path %r{\A/rechnungen/\d+\z}
    assert_equal 800.to_d, Invoice.order(:id).last.total
    assert_equal order.id, Invoice.order(:id).last.sales_document_id
  end

  test "telefonischer Auftrag braucht kein Angebot und erlaubt einen festen Anzahlungsbetrag" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    visit new_sales_document_path(kind: "order")
    fill_parties
    fill_in "invoice_invoice_lines_attributes_0_description", with: "Telefonisch vereinbarter Auftrag"
    select "Pauschal", from: "invoice_invoice_lines_attributes_0_unit_code"
    fill_in "invoice_invoice_lines_attributes_0_unit_price", with: "800,00"
    click_button "Auftrag speichern"
    assert_selector "h1", text: /Auftrag AU-/
    assert_nil SalesDocument.order(:id).last.source_offer_id
    click_link "Anzahlung berechnen"
    select "Fester Betrag", from: "Berechnen nach"
    fill_in "Jetzt berechnen in Euro", with: "400,00"
    assert_selector "[data-order-billing-target=requested]", text: "400,00"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    page.execute_script("arguments[0].scrollIntoView({behavior: 'instant'})", find("[data-order-billing-target=panel]"))
    page.save_screenshot(Rails.root.join("tmp/screenshots/order-fixed-advance-mobile.png"))
    click_button "Festschreiben"
    assert_current_path %r{\A/rechnungen/\d+\z}
    assert_equal 400.to_d, Invoice.order(:id).last.total
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "Angebot und Auftrag nutzen Kundensuche Stundensaetze und den gemeinsamen Editor" do
    visit new_sales_document_path
    fill_parties
    fill_in "Allgemeiner Stundensatz (EUR pro Stunde, optional)", with: "80,00"
    fill_in "Individueller Stundensatz", with: "95,00"
    fill_in "invoice_invoice_lines_attributes_0_description", with: "Beratung"
    assert_field "invoice_invoice_lines_attributes_0_unit_price", with: "95,00"
    assert_selector "trix-editor"
    assert_no_field "invoice_paid"
    assert_field "invoice-number-preview", with: "AN-#{Date.current.year}-0001"
    click_button "Angebot speichern"
    assert_current_path %r{\A/angebote-und-auftraege/\d+\z}
    offer = SalesDocument.order(:id).last
    assert_current_path sales_document_path(offer)
    assert_equal "95.0", offer.data["buyer_hourly_rate"]
    click_link "Bearbeiten"
    assert_selector "input#invoice_issued_on[value='#{offer.document_date.iso8601}']", visible: :all
    fill_in "Angebotstitel (optional)", with: "Überarbeitetes Angebot"
    page.execute_script("window.dispatchEvent(new KeyboardEvent('keydown', { key: 's', ctrlKey: true, cancelable: true }))")
    assert_current_path sales_document_path(offer)
    assert_equal "Überarbeitetes Angebot", offer.reload.title

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    visit new_sales_document_path(kind: "order")
    fill_in "invoice_buyer_name", with: "Testkund"
    find("#customer-name-suggestions li", text: "Testkundin").click
    assert_field "invoice_buyer_street", with: "Kundenweg 2"
    assert_field "invoice_invoice_lines_attributes_0_unit_price", with: "95,00"
    fill_in "invoice_invoice_lines_attributes_0_description", with: "Weitere Beratung"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    page.execute_script("arguments[0].scrollIntoView({behavior: 'instant'})", find("#invoice-step-buyer"))
    page.save_screenshot(Rails.root.join("tmp/screenshots/shared-order-form-mobile.png"))
    click_button "Auftrag speichern"
    assert_current_path %r{\A/angebote-und-auftraege/\d+\z}
    assert_current_path sales_document_path(SalesDocument.order(:id).last)
    assert_equal offer.data["customer_id"], SalesDocument.order(:id).last.data["customer_id"]
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "Rechnungsuebersicht bietet Angebote und Auftraege und Auftrag uebernimmt ausgewaehltes Angebot" do
    visit invoices_path
    click_link "Angebot erstellen"
    assert_current_path new_sales_document_path
    fill_parties
    fill_in "invoice_invoice_lines_attributes_0_description", with: "Vereinbarter Umfang"
    select "Pauschal", from: "invoice_invoice_lines_attributes_0_unit_code"
    fill_in "invoice_invoice_lines_attributes_0_unit_price", with: "800,00"
    click_button "Angebot speichern"
    assert_current_path %r{\A/angebote-und-auftraege/\d+\z}
    offer = SalesDocument.order(:id).last
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    visit invoices_path
    click_link "Auftrag erstellen"
    find("#source_offer_id option", text: offer.document_number).select_option
    click_button "Als Auftrag übernehmen"
    assert_current_path %r{\A/angebote-und-auftraege/\d+\z}
    order = SalesDocument.order(:id).last
    assert_equal offer.id, order.source_offer_id
    assert_equal 800.to_d, order.total_amount
    assert_text "Vereinbarter Umfang"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "Angebot und Auftrag verwenden dasselbe Nummernpopup mit passenden Platzhaltern" do
    %w[offer order].each do |kind|
      visit new_sales_document_path(kind: kind)
      fill_parties
      label = kind == "offer" ? "Angebotsnummer" : "Auftragsnummer"
      find("#invoice-number-preview").click
      assert_selector "dialog[open] h3", text: "#{label}nformat bearbeiten"
      assert_selector "#invoice-number-format-preview", text: "#{InvoiceNumber::TYPE_CODES.fetch(kind)}-#{Date.current.year}-0001"
      assert_selector "[data-invoice-number-target=globalFormatNotice]", text: "Grundlage ist dein Rechnungsnummernformat"
      fill_in "Dein Format", with: "EIGEN-[Fortlaufendenummer]"
      assert_selector ".number-format-notice.invoice-status", text: "Angepasst: Dieses Format weicht"
      fill_in "Dein Format", with: InvoiceNumber::DEFAULT_FORMAT
      assert_no_selector ".number-format-notice.invoice-status"
      fill_in "Dein Format", with: "[Rechnungsart]-[Jahr]-[Fortlaufendenummer]-[Kundenkürzel]"
      assert_selector ".number-format-notice.invoice-status", text: "Angepasst: Dieses Format weicht"
      fill_in "invoice-number-abbreviation-editor", with: "TEST"
      fill_in "Zuletzt verwendete fortlaufende Nummer", with: "99"
      expected = "#{InvoiceNumber::TYPE_CODES.fetch(kind)}-#{Date.current.year}-0100-TEST"
      assert_selector "#invoice-number-format-preview", text: expected
      find("button[aria-label='Bearbeitung der #{label} schließen']").click
      assert_selector "[data-invoice-number-target=customFormatFlag]", text: "Angepasstes Format"
      fill_in "invoice_invoice_lines_attributes_0_description", with: "Vereinbarter Umfang"
      select "Pauschal", from: "invoice_invoice_lines_attributes_0_unit_code"
      fill_in "invoice_invoice_lines_attributes_0_unit_price", with: "800,00"
      click_button "#{kind == 'offer' ? 'Angebot' : 'Auftrag'} speichern"
      assert_current_path %r{\A/angebote-und-auftraege/\d+\z}
      document = SalesDocument.order(:id).last
      assert_equal expected, document.document_number
      click_link "Bearbeiten"
      assert_field "invoice-number-preview", with: expected
      fill_in "#{document.label}stitel (optional)", with: "Aktualisiert"
      click_button "#{document.label} speichern"
      assert_current_path sales_document_path(document)
      assert_equal expected, document.reload.document_number
    end
  end

  test "Gesamtanteil bleibt einfach und Positionsanteile ueberleben Wechsel und Entwurf" do
    visit new_invoice_path
    fill_parties
    choose "Anzahlungsrechnung"
    within first("[data-invoice-lines-target=row]") do
      fill_in "Titel", with: "Material"
      select "Pauschal", from: "Einheit"
      fill_in "Pauschalpreis", with: "300,00"
    end
    click_button "Position hinzufügen"
    within all("[data-invoice-lines-target=row]").last do
      fill_in "Titel", with: "Umsetzung"
      fill_in "Pauschalpreis", with: "500,00"
    end
    assert_checked_field "invoice_allocation_basis_total"
    assert_no_selector ".position-allocation"
    assert_selector "[data-order-billing-target=requested]", text: "400,00"
    select "Fester Betrag", from: "Berechnen nach"
    fill_in "Jetzt berechnen in Euro", with: "300,00"
    assert_selector "[data-order-billing-target=requested]", text: "300,00"
    choose "invoice_allocation_basis_positions"
    assert_selector ".invoice-line .position-allocation", count: 2
    within all(".position-allocation").first do
      fill_in "Anteil", with: "50,00"
      assert_field "Anteil", with: "50,00"
    end
    assert_selector "[data-order-billing-target=requested]", text: "150,00"
    within all(".position-allocation").last do
      select "Fester Betrag in Euro", from: "Berechnen nach"
      fill_in "Anteil", with: "125,00"
    end
    assert_selector "[data-order-billing-target=requested]", text: "275,00"
    choose "invoice_allocation_basis_total"
    assert_no_selector ".position-allocation"
    assert_selector "[data-order-billing-target=requested]", text: "300,00"
    choose "invoice_allocation_basis_positions"
    assert_selector "[data-order-billing-target=requested]", text: "275,00"
    click_link "Später"
    assert_current_path invoices_path
    find(".invoice-draft-card__link", text: "Entwurf").click
    assert_checked_field "invoice_allocation_basis_positions"
    assert_selector "[data-order-billing-target=requested]", text: "275,00"
    within all(".position-allocation").last { assert_field "Anteil", with: "125,00" }
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    page.execute_script("arguments[0].scrollIntoView({behavior: 'instant'})", find("[data-order-billing-target=panel]"))
    page.save_screenshot(Rails.root.join("tmp/screenshots/position-advance-mobile.png"))
    click_button "Festschreiben"
    assert_current_path %r{\A/rechnungen/\d+\z}
    invoice = Invoice.order(:id).last
    assert_equal 275.to_d, invoice.total
    assert_equal [ 150.to_d, 125.to_d ], invoice.invoice_lines.map(&:line_total)
    assert_equal 800.to_d, invoice.sales_document.total_amount
    visit sales_document_path(invoice.sales_document)
    click_link "Abschlagsrechnung erstellen"
    choose "invoice_allocation_basis_positions"
    within all(".position-allocation").first do
      assert_text "Noch nicht abgerechnet: 150,00"
      select "Fester Betrag in Euro", from: "Berechnen nach"
      fill_in "Anteil", with: "150,00"
    end
    assert_selector "[data-order-billing-target=requested]", text: "150,00"
    click_button "Festschreiben"
    assert_current_path %r{\A/rechnungen/\d+\z}
    assert_equal 150.to_d, Invoice.order(:id).last.total
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "direkte Anzahlungen werden bei der Schlussrechnung ausgewaehlt und zusammengefuehrt" do
    source_ids = []
    [ 300, 100 ].each do |amount|
      visit new_invoice_path
      fill_parties
      choose "Anzahlungsrechnung"
      choose "invoice_allocation_basis_direct"
      assert_no_selector "[data-order-billing-target=calculation]"
      assert_selector "[data-order-billing-target=scopeHint]", text: "Den vollständigen Auftrag erfasst du später"
      within first("[data-invoice-lines-target=row]") do
        fill_in "Titel", with: "Anzahlung für vereinbarte Anpassungen"
        select "Pauschal", from: "Einheit"
        fill_in "Pauschalpreis", with: amount.to_s
      end
      check "Bereits vollständig bezahlt"
      fill_in "invoice_received_on_display", with: Date.current.strftime("%d.%m.%Y")
      click_button "Festschreiben"
      assert_current_path %r{\A/rechnungen/\d+\z}
      source = Invoice.order(:id).last
      assert_nil source.sales_document_id
      source_ids << source.id
    end
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    visit invoices_path
    click_link "Schlussrechnung erstellen"
    assert_checked_field "invoice_billing_kind_final"
    fill_in "invoice_buyer_name", with: "Testkund"
    find("#customer-name-suggestions li", text: "Testkundin").click
    source_ids.each { |id| check "settlement-#{id}" }
    assert_selector "[data-settlement-selection-target=sum]", text: "400,00"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    page.execute_script("arguments[0].scrollIntoView({behavior: 'instant'})", find(".settlement-selection"))
    page.save_screenshot(Rails.root.join("tmp/screenshots/final-selection-mobile.png"))
    within first("[data-invoice-lines-target=row]") do
      fill_in "Titel", with: "Vollständige Anpassungen"
      select "Pauschal", from: "Einheit"
      fill_in "Pauschalpreis", with: "800,00"
    end
    click_link "Später"
    assert_current_path invoices_path
    find(".invoice-draft-card__link", text: "Entwurf").click
    assert_checked_field "invoice_billing_kind_final"
    source_ids.each { |id| assert_checked_field "settlement-#{id}" }
    click_button "Vorschau"
    within_frame("invoice-preview-frame") do
      assert_selector ".invoice-pages .invoice-table tfoot", text: "400,00"
      assert_selector ".invoice-pages .invoice-table tfoot", text: "Abzüglich Zahlung", count: 1
    end
    click_button "Vorschau schließen"
    click_button "Festschreiben"
    assert_current_path %r{\A/rechnungen/\d+\z}
    final = Invoice.order(:id).last
    assert_equal 800.to_d, final.total
    assert_equal 400.to_d, final.deducted_total
    assert_equal 400.to_d, final.payment_total
    source_ids.each { |id| assert Invoice.find(id).settled_in_final? }
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  private

  def fill_parties
    find(".invoice-seller-details > summary").click if page.has_selector?(".invoice-seller-details > summary", wait: 0) && page.has_no_selector?("#invoice_seller_name", wait: 0)
    find("details > summary", text: "Deine Angaben").click if page.has_no_selector?("#invoice_seller_name", wait: 0)
    { seller_name: "Teststudio", seller_street: "Teststraße 1", seller_postal_code: "10115", seller_city: "Berlin", seller_tax_identifier: "12/345/67890", seller_email: "studio@example.test",
      buyer_name: "Testkundin", buyer_street: "Kundenweg 2", buyer_postal_code: "10115", buyer_city: "Berlin", buyer_email: "kundin@example.test" }.each do |field, value|
      fill_in "invoice_#{field}", with: value
    end
  end
end
