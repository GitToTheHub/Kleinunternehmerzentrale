require "application_system_test_case"

class InvoiceFormTest < ApplicationSystemTestCase
  test "Text in Nummernvorlagen ist mit der Maus markierbar ohne das Format zu wechseln" do
    fill_invoice
    find("#invoice-number-preview").click
    template = find('.invoice-number-template[data-format="[Jahr]-[Monat]-[Tag]-[Fortlaufendenummer]"]')
    assert_equal "div", template.tag_name
    assert_equal "button", template[:role]
    text = template.find("strong")
    original = find("#invoice-number-format-editor").value
    page.driver.browser.action.move_to(text.native, -text.rect.width / 2 + 2, 0).click_and_hold.move_by(90, 0).release.perform
    assert page.evaluate_script("window.getSelection().toString().length > 0")
    assert_field "Dein Format", with: original
    page.execute_script("window.getSelection().removeAllRanges()")
    template.send_keys(:enter)
    assert_field "Dein Format", with: "[Jahr]-[Monat]-[Tag]-[Fortlaufendenummer]"
  end

  test "angepasstes Rechnungsformat zeigt im Formular den Geltungsbereich" do
    fill_invoice
    find("#invoice-number-preview").click
    fill_in "Dein Format", with: "EIGEN-[Jahr]-[Fortlaufendenummer]"
    check "invoice_invoice_number_format_once"
    assert_selector "#invoice-number-editor .number-format-notice", text: "Angepasstes Format, gilt nur für diese Rechnung"
    assert_selector "#invoice-number-editor .number-format-notice", text: "Rechnungsart entfernt."
    assert_selector "#invoice-number-editor .number-format-notice", text: "Fester Text geändert."
    find("button[aria-label='Bearbeitung der Rechnungsnummer schließen']").click
    assert_selector ".number-format-custom", text: "Angepasstes Format, gilt nur für diese Rechnung"
    find("#invoice-number-preview").click
    uncheck "invoice_invoice_number_format_once"
    assert_selector "#invoice-number-editor .number-format-notice", text: "Angepasstes Format, wird als globale Vorgabe gespeichert"
    find("button[aria-label='Bearbeitung der Rechnungsnummer schließen']").click
    assert_selector ".number-format-custom", text: "Angepasstes Format, wird als globale Vorgabe gespeichert"
    find("#invoice-number-preview").click
    click_button "Änderungen rückgängig machen"
    assert_field "Dein Format", with: InvoiceNumber::DEFAULT_FORMAT
    assert_no_selector ".number-format-custom"
    assert_no_button "Änderungen rückgängig machen"
  end

  test "Aktionsleiste bleibt auf verschiedenen Smartphones kompakt und bedienbar" do
    resize_browser(414, 720)
    fill_invoice
    assert_selector "[data-invoice-draft-target=status]", text: "Entwurf gespeichert"
    footer = find(".invoice-form__actions")
    assert_button "Festschreiben"
    assert_button "Vorschau"
    assert_link "Später"
    assert_selector ".invoice-form__actions .button svg[aria-hidden=true]", count: 4
    assert_selector "[data-invoice-draft-target=discardIcon]:not([hidden])"
    assert_selector "[data-invoice-draft-target=cancelIcon][hidden]", visible: :all
    [ 320, 360, 375, 390, 414, 430 ].each do |width|
      resize_browser(width, 720)
      metrics = footer.evaluate_script(<<~JS)
        ({ height: this.getBoundingClientRect().height,
           buttons: Array.from(this.querySelectorAll('.button:not([hidden])')).map(button => ({
             top: button.getBoundingClientRect().top, height: button.getBoundingClientRect().height,
             fits: button.scrollWidth <= button.clientWidth
           })) })
      JS
      assert_operator metrics["height"], :<=, (width <= 360 ? 168 : 144)
      assert_in_delta metrics["buttons"][0]["top"], metrics["buttons"][1]["top"], 1
      assert_in_delta metrics["buttons"][2]["top"], metrics["buttons"][3]["top"], 1
      metrics["buttons"].each do |button|
        assert_operator button["height"], :>=, 44
        assert button["fits"]
      end
      assert_no_horizontal_overflow
      page.save_screenshot(Rails.root.join("tmp/screenshots/invoice-actions-#{width}.png")) if [ 320, 390, 430 ].include?(width)
    end
    resize_browser(740, 360)
    assert_equal "static", footer.evaluate_script("getComputedStyle(this).position")
    assert_no_horizontal_overflow
    resize_browser(390, 720)
    click_button "Vorschau"
    assert_selector "dialog.invoice-preview-dialog[open]"
    click_button "Vorschau schließen"
    click_link "Später"
    assert_current_path invoices_path
    assert_selector ".invoice-draft-card", count: 1
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.current_window.resize_to(1400, 1100)
  end

  test "Auswahlkarten zeigen Hover und Tastaturfokus ohne sichtbare Radiokreise" do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "hover", value: "hover" } ])
    card = find("#billing-kind-cards label", text: "Anzahlungsrechnung")
    radio = card.find("input[type=radio]")
    assert_equal "inset(50%)", radio.evaluate_script("getComputedStyle(this).clipPath")
    card.evaluate_script("this.scrollIntoView({block: 'center', behavior: 'instant'})")
    before = card.evaluate_script("getComputedStyle(this).backgroundColor")
    card.hover
    assert_selector "#billing-kind-cards label:hover"
    assert_not_equal before, card.evaluate_script("getComputedStyle(this).backgroundColor")
    card.click
    assert_checked_field "invoice_billing_kind_advance"
    find("#invoice_billing_kind_regular").send_keys(:arrow_right)
    assert_checked_field "invoice_billing_kind_advance"
    assert card.evaluate_script("this.matches(':has(input:focus-visible)')")
    page.save_screenshot(Rails.root.join("tmp/screenshots/invoice-kind-cards.png"))
    page.current_window.resize_to(390, 844)
    find("#billing-kind-cards label", text: "Abschlagsrechnung").click
    assert_checked_field "invoice_billing_kind_progress"
    assert_no_horizontal_overflow
    page.save_screenshot(Rails.root.join("tmp/screenshots/invoice-kind-cards-mobile.png"))
  ensure
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    page.current_window.resize_to(1400, 1100)
  end

  test "Anzahlung und mobile Schlussrechnung erklaeren den Ablauf und rechnen Zahlungen an" do
    fill_invoice
    assert_no_selector "select[name='invoice[billing_kind]']"
    assert_no_text "Mit einer normalen Rechnung rechnest du eine Leistung vollständig ab."
    assert_no_link "Anzahlung, Abschlag oder echte Teilrechnung?"
    assert_no_text "Weitere Abschlagsrechnungen und die Schlussrechnung zu diesem Auftrag"
    assert_no_text "Teil- und Schlussrechnungen unterstützt die App"
    assert_selector "[data-billing-kind-target=issuedOnHint]", text: "Trage den Tag ein, an dem du die Rechnung ausstellst. Das Leistungsdatum gibst du separat an."
    choose "Anzahlungsrechnung"
    assert_selector "[data-billing-kind-target=issuedOnHint]", text: "Trage den Tag ein, an dem du die Anzahlungsrechnung ausstellst. Die Leistung kann später erfolgen."
    assert_selector "#billing-kind-cards .booking-type-option", text: "Dein Kunde zahlt einen Teil im Voraus"
    assert_field "Voraussichtliche Leistung am / von"
    assert_field "Voraussichtlich bis (optional)"
    assert_no_selector "#billing-kind-help"
    choose "invoice_billing_kind_regular"
    assert_selector "[data-billing-kind-target=issuedOnHint]", text: "Trage den Tag ein, an dem du die Rechnung ausstellst. Das Leistungsdatum gibst du separat an."
    assert_no_text "Weitere Abschlagsrechnungen und die Schlussrechnung zu diesem Auftrag"
    assert_no_text "Teil- und Schlussrechnungen unterstützt die App"
    assert_field "Leistungsdatum / Leistung von"
    assert_field "Leistung bis (optional)"
    choose "Anzahlungsrechnung"
    assert_selector "#billing-kind-cards .booking-type-option", count: 3
    assert_checked_field "Anzahlungsrechnung"
    choose "Abschlagsrechnung"
    assert_selector "[data-billing-kind-target=issuedOnHint]", text: "Trage den Tag ein, an dem du die Abschlagsrechnung ausstellst. Der Auftrag muss noch nicht abgeschlossen sein."
    assert_field "Leistungsdatum / Leistung von"
    assert_selector "#billing-kind-cards .booking-type-option", count: 3
    choose "Anzahlungsrechnung"
    assert_checked_field "Anzahlungsrechnung"
    assert_no_button "Rechnungsart ändern"
    assert_field "Voraussichtliche Leistung am / von"
    assert_no_selector "[data-billing-kind-target=staged]"
    page.execute_script("arguments[0].scrollIntoView({behavior: 'instant'})", find("#billing-kind-cards"))
    page.save_screenshot(Rails.root.join("tmp/screenshots/billing-kind-desktop.png"))
    assert_selector "#invoice_title:not([required])"
    assert_field "Rechnungstitel (optional)", with: ""
    # Simulate an older draft whose positions already contain the requested amount.
    page.execute_script("const field = document.querySelector('[name=\"invoice[order_based]\"]'); field.value = '0'; field.dispatchEvent(new Event('change', {bubbles: true}))")
    fill_in line_id("unit_price"), with: "300"
    select "Andere Zahlungsart", from: "Zahlungsart"
    fill_in "invoice_service_on_display", with: "01.11.2026"
    fill_in "invoice_service_until_on_display", with: "30.11.2026"
    click_button "Festschreiben"
    assert_selector ".print-invoice__title .eyebrow", text: "Anzahlungsrechnung", visible: :all
    assert_selector ".print-invoice .invoice-meta", text: "Voraussichtlicher Leistungszeitraum", visible: :all
    assert_selector ".print-invoice .invoice-meta", text: "01.11.2026 bis 30.11.2026", visible: :all
    advance = Invoice.order(:id).last
    advance.workspace.bookkeeping_entries.create!(kind: "income", category: "income_small", invoice: advance,
      paid_on: Date.current, amount: 300, description: "Anzahlung Website", payment_account: "business")
    visit invoice_path(advance)
    click_link "Schlussrechnung erstellen"
    resize_browser(390, 844)
    assert_checked_field "Schlussrechnung"
    assert_selector "#invoice_title:not([required])"
    assert_field "Rechnungstitel (optional)", with: ""
    assert_field "invoice-number-preview", with: "SR-#{Date.current.year}-0002"
    assert_selector "[data-billing-kind-target=issuedOnHint]", text: "Trage den Tag ein, an dem du die Schlussrechnung ausstellst. Das kann ein anderer Tag als die Fertigstellung sein."
    assert_selector "#billing-kind-cards .booking-type-option", count: 3
    assert_selector "#billing-kind-cards .booking-type-option", text: "Du rechnest den gesamten Auftrag ab. Bereits erhaltene Zahlungen werden abgezogen."
    assert_no_horizontal_overflow
    page.execute_script("arguments[0].scrollIntoView({behavior: 'instant'})", find("#billing-kind-cards"))
    page.save_screenshot(Rails.root.join("tmp/screenshots/billing-kind-mobile.png"))
    fill_in line_id("description"), with: "Website vollständig erstellt"
    fill_in line_id("unit_price"), with: "1.000,00"
    click_button "Festschreiben"
    assert_selector ".print-invoice__title .eyebrow", text: "Schlussrechnung", visible: :all
    assert_selector ".print-invoice tfoot", text: "Abzüglich Zahlung zu #{advance.invoice_number}", visible: :all
    assert_selector ".print-invoice tfoot", text: "700,00", visible: :all
    assert_equal 700, Invoice.order(:id).last.payment_total
    assert_no_horizontal_overflow
    assert_selector ".invoice-pages", text: "Restbetrag"
    page.execute_script("arguments[0].scrollIntoView({behavior: 'instant'})", find(".invoice-pages"))
    page.save_screenshot(Rails.root.join("tmp/screenshots/staged-invoice-mobile.png"))
  end

  test "Formularhinweis schliesst mit kleinem Abstand an die Einleitung an" do
    gap = page.evaluate_script <<~JS
      (() => {
        const introduction = document.querySelector('main > h1 + p').getBoundingClientRect();
        const note = document.querySelector('.invoice-form > .form-note').getBoundingClientRect();
        return note.top - introduction.bottom;
      })()
    JS
    assert_operator gap, :<=, 20
  end

  test "allgemeiner Stundensatz ist sichtbar einstellbar und fuellt Stundenpositionen" do
    fill_invoice
    select "Stunde", from: line_id("unit_code")
    fill_in line_id("unit_price"), with: "0"
    page.execute_script("document.querySelector('.invoice-seller-details').open = true")
    fill_in "invoice_seller_hourly_rate", with: "95,50"
    assert_field line_id("unit_price"), with: "95,50"
    find(".invoice-seller-details > summary").click
    assert_selector ".invoice-seller-summary", text: "Allgemeiner Stundensatz: 95,50"
    find(".invoice-seller-details > summary").click
    assert_text "Leer lassen, wenn du nicht nach Stunden abrechnest."
    fill_in line_id("unit_price"), with: "120"
    fill_in "invoice_seller_hourly_rate", with: "100"
    assert_field line_id("unit_price"), with: "120,00"
    click_button "Festschreiben"
    assert_selector ".print-invoice"
    assert_equal 100, Invoice.last.workspace.business_profile.hourly_rate
    visit new_invoice_path
    page.execute_script("document.querySelector('.invoice-seller-details').open = true")
    assert_field "invoice_seller_hourly_rate", with: "100,00"
    select "Stunde", from: line_id("unit_code")
    assert_field line_id("unit_price"), with: "100,00"
  end

  test "individueller Stundensatz faellt bei leerem Feld auf die allgemeine Vorgabe zurueck" do
    fill_invoice
    select "Stunde", from: line_id("unit_code")
    fill_in line_id("unit_price"), with: "0"
    page.execute_script("document.querySelector('.invoice-seller-details').open = true")
    fill_in "invoice_seller_hourly_rate", with: "80"
    assert_field line_id("unit_price"), with: "80,00"
    fill_in "Individueller Stundensatz", with: "95,50"
    assert_field line_id("unit_price"), with: "95,50"
    fill_in "Individueller Stundensatz", with: ""
    assert_field line_id("unit_price"), with: "80,00"
    click_button "Festschreiben"
    assert_selector ".print-invoice"
    assert_nil Invoice.last.customer.hourly_rate
  end

  test "Bankfelder werden nur bei Ueberweisung angeboten" do
    fill_invoice
    select "Barzahlung", from: "Zahlungsart"
    assert_no_selector "#invoice_iban"
    assert_no_selector "#invoice_bic"
    select "Überweisung", from: "Zahlungsart"
    assert_selector "#invoice_iban:required:enabled"
    assert_no_selector "#invoice_bic"
    select "Vereinigte Staaten", from: "invoice_buyer_country"
    assert_selector "#invoice_bic:enabled"
    select "Andere Zahlungsart", from: "Zahlungsart"
    assert_no_selector "#invoice_iban"
    assert_no_selector "#invoice_bic"
  end

  test "nummerierte Listen lassen sich einruecken und bleiben in Vorschau und Klartext erhalten" do
    resize_browser(390, 844)
    fill_invoice
    editor = find("trix-editor")
    editor.click
    within(".rich-text__toolbar") { click_button "Nummerierte Liste" }
    editor.send_keys("Erster Punkt", :enter, "Unterpunkt")
    within(".rich-text__toolbar") { click_button "Einrücken" }
    assert_selector "trix-editor ol > li > ol > li", text: "Unterpunkt"
    within(".rich-text__toolbar") { click_button "Ausrücken" }
    assert_no_selector "trix-editor ol > li > ol"
    within(".rich-text__toolbar") { click_button "Einrücken" }
    assert_selector "trix-editor ol > li > ol > li", text: "Unterpunkt"
    editor.send_keys(:enter, "Weiterer Unterpunkt")
    assert_selector "trix-editor ol > li > ol > li", count: 2
    assert_no_horizontal_overflow
    page.save_screenshot(Rails.root.join("tmp/screenshots/action-text-numbered-lists-mobile.png"))
    click_button "Vorschau"
    within_frame("invoice-preview-frame") do
      assert_selector ".invoice-pages .invoice-line-details ol > li > ol > li", count: 2
    end
    click_button "Vorschau schließen"
    click_button "Festschreiben"
    assert_current_path %r{\A/rechnungen/\d+\z}
    assert_equal "1. Erster Punkt\n  1. Unterpunkt\n  2. Weiterer Unterpunkt", Invoice.order(:id).last.invoice_lines.sole.details_text
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.current_window.resize_to(1400, 1100)
  end

  test "Speicher Tastenkombination verhindert Browserdialog und sichert den Entwurf" do
    fill_invoice
    editor = find("trix-editor")
    editor.click
    [ :control, :meta ].each_with_index do |modifier, index|
      editor.send_keys("Gespeicherter Text #{index}")
      page.execute_script(<<~JS)
        window.saveKeyPrevented = null;
        window.addEventListener('keydown', function captureSave(event) {
          if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's') {
            window.saveKeyPrevented = event.defaultPrevented;
            window.removeEventListener('keydown', captureSave, true);
          }
        }, { capture: true });
      JS
      editor.send_keys([ modifier, "s" ])
      assert_selector "[data-invoice-draft-target=status]", text: "Entwurf gespeichert"
      assert_equal true, page.evaluate_script("window.saveKeyPrevented")
      assert_includes InvoiceDraft.active.sole.data.fetch("invoice_lines_attributes").fetch("0").fetch("details"), "Gespeicherter Text #{index}"
      assert_current_path %r{\A/rechnungen/entwuerfe/\d+/bearbeiten\z}
      assert_no_selector "dialog[open]"
    end
  end

  test "Action Text behaelt Formatierungen in Entwurf Vorschau und XRechnung" do
    fill_invoice
    editor = find("trix-editor.rich-text__editor")
    editor.click
    within ".rich-text__toolbar" do
      assert_selector "button[data-trix-attribute]", count: 5
      click_button "Fett"
    end
    editor.send_keys("Fetter Text")
    within(".rich-text__toolbar") { click_button "Fett" }
    editor.send_keys(" ")
    within(".rich-text__toolbar") { click_button "Kursiv" }
    editor.send_keys("Kursiver Text")
    assert_selector "trix-editor strong", text: "Fetter Text"
    assert_selector "trix-editor em", text: "Kursiver Text"
    resize_browser(390, 844)
    editor.evaluate_script("this.scrollIntoView({block: 'center', behavior: 'instant'})")
    assert_no_horizontal_overflow
    page.save_screenshot(Rails.root.join("tmp/screenshots/action-text-mobile.png"))
    click_link "Später"
    assert_current_path invoices_path
    find(".invoice-draft-card__link").click
    assert_selector "trix-editor strong", text: "Fetter Text"
    assert_selector "trix-editor em", text: "Kursiver Text"
    click_button "Vorschau"
    within_frame("invoice-preview-frame") do
      assert_selector ".invoice-pages .invoice-line-details strong", text: "Fetter Text"
      assert_selector ".invoice-pages .invoice-line-details em", text: "Kursiver Text"
    end
    click_button "Vorschau schließen"
    click_button "Festschreiben"
    assert_current_path %r{\A/rechnungen/\d+\z}
    invoice = Invoice.order(:id).last
    xml = Nokogiri::XML(XrechnungGenerator.new(invoice).call)
    assert_includes xml.xpath("//*[local-name()='SpecifiedTradeProduct']/*[local-name()='Description']").map(&:text).join(" "), "Fetter Text"
    assert_includes invoice.invoice_lines.sole.details_text, "Kursiver Text"
  end

  test "Links bleiben in Entwurf Vorschau XRechnung und Datenexport erhalten" do
    resize_browser(390, 844)
    fill_invoice
    editor = find("trix-editor")
    editor.click
    editor.send_keys("Projektwebsite")
    editor.evaluate_script("this.editor.setSelectedRange([0, 14])")
    within(".rich-text__toolbar") { click_button "Link" }
    find(".rich-text__link-dialog[data-trix-active] input[name=href]").set("https://example.de/projekt?a=1&b=2")
    assert_no_horizontal_overflow
    page.save_screenshot(Rails.root.join("tmp/screenshots/action-text-link-mobile-open.png"))
    within(".rich-text__link-dialog[data-trix-active]") { click_button "Übernehmen" }
    assert_selector "trix-editor a[href='https://example.de/projekt?a=1&b=2']", text: "Projektwebsite"
    assert_no_horizontal_overflow
    page.save_screenshot(Rails.root.join("tmp/screenshots/action-text-link-mobile.png"))
    click_link "Später"
    assert_current_path invoices_path
    find(".invoice-draft-card__link").click
    assert_selector "trix-editor a", text: "Projektwebsite"
    click_button "Vorschau"
    within_frame("invoice-preview-frame") do
      assert_selector ".invoice-pages .invoice-line-details a[href='https://example.de/projekt?a=1&b=2'][target=_blank][rel='noopener noreferrer']", text: "Projektwebsite"
    end
    click_button "Vorschau schließen"
    click_button "Festschreiben"
    assert_current_path %r{\A/rechnungen/\d+\z}
    invoice = Invoice.order(:id).last
    expected = "Projektwebsite (https://example.de/projekt?a=1&b=2)"
    xml = Nokogiri::XML(XrechnungGenerator.new(invoice).call)
    assert_equal expected, xml.xpath("//*[local-name()='SpecifiedTradeProduct']/*[local-name()='Description']").text
    Zip::File.open_buffer(DataExport.new(invoice.workspace).call) do |zip|
      assert_includes zip.read("positionen.csv"), expected
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.current_window.resize_to(1400, 1100)
  end

  test "Linkadressen ohne Protokoll funktionieren und Fehler bleiben in beiden Farbschemata lesbar" do
    editor = find("trix-editor")
    editor.click
    editor.send_keys("Projektwebsite")
    editor.evaluate_script("this.editor.setSelectedRange([0, 14])")
    [ "light", "dark" ].each do |scheme|
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: scheme } ])
      within(".rich-text__toolbar") { click_button "Link" }
      input = find(".rich-text__link-dialog[data-trix-active] input[name=href]")
      input.set("keine adresse")
      within(".rich-text__link-dialog[data-trix-active]") { click_button "Übernehmen" }
      assert_selector ".rich-text__link-dialog input[name=href][data-trix-validate]:invalid"
      assert input.evaluate_script(<<~JS)
        (() => {
          const style = getComputedStyle(this);
          const theme = getComputedStyle(document.documentElement);
          const probe = document.createElement('span');
          document.body.append(probe);
          probe.style.color = theme.getPropertyValue('--ink');
          const ink = getComputedStyle(probe).color;
          probe.style.color = theme.getPropertyValue('--error-bg');
          const background = getComputedStyle(probe).color;
          probe.remove();
          return style.color === ink && style.backgroundColor === background;
        })()
      JS
      page.save_screenshot(Rails.root.join("tmp/screenshots/action-text-link-error-#{scheme}.png"))
      input.set("google.de")
      assert_no_selector ".rich-text__link-dialog input[name=href][data-trix-validate]"
      if scheme == "light"
        within(".rich-text__link-dialog[data-trix-active]") { click_button "Übernehmen" }
      else
        input.send_keys(:enter)
      end
      assert_selector "trix-editor a[href='https://google.de']"
      editor.evaluate_script("this.editor.setSelectedRange([1, 1])")
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  test "Linkdialog zeigt und aendert Anzeigetext auch ohne vorherige Textauswahl" do
    resize_browser(390, 844)
    fill_invoice
    editor = find("trix-editor")
    editor.click
    within(".rich-text__toolbar") { click_button "Link" }
    assert_field "Anzeigetext", with: ""
    fill_in "Anzeigetext", with: "Projektwebsite"
    fill_in "Linkadresse", with: "example.de"
    within(".rich-text__link-dialog[data-trix-active]") { click_button "Übernehmen" }
    assert_selector "trix-editor a[href='https://example.de']", exact_text: "Projektwebsite"
    assert_equal "Projektwebsite", editor.text
    editor.evaluate_script("this.editor.setSelectedRange([3, 3])")
    within(".rich-text__toolbar") { click_button "Link" }
    assert_field "Anzeigetext", with: "Projektwebsite"
    assert_field "Linkadresse", with: "https://example.de"
    fill_in "Anzeigetext", with: "Neue Projektseite"
    fill_in "Linkadresse", with: "example.de/neu"
    assert_no_horizontal_overflow
    page.save_screenshot(Rails.root.join("tmp/screenshots/action-text-link-display-text.png"))
    within(".rich-text__link-dialog[data-trix-active]") { click_button "Übernehmen" }
    assert_selector "trix-editor a[href='https://example.de/neu']", exact_text: "Neue Projektseite"
    assert_equal "Neue Projektseite", editor.text
    click_link "Später"
    assert_current_path invoices_path
    find(".invoice-draft-card__link").click
    assert_selector "trix-editor a", exact_text: "Neue Projektseite"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.current_window.resize_to(1400, 1100)
  end

  test "Anzeigetext wird vor Uebernahme nicht geaendert und leerer Text nutzt die Adresse" do
    editor = find("trix-editor")
    editor.click
    editor.send_keys("Projektwebsite")
    editor.evaluate_script("this.editor.setSelectedRange([0, 14])")
    within(".rich-text__toolbar") { click_button "Link" }
    assert_field "Anzeigetext", with: "Projektwebsite"
    fill_in "Anzeigetext", with: "Anderer Text"
    fill_in "Linkadresse", with: "keine adresse"
    within(".rich-text__link-dialog[data-trix-active]") { click_button "Übernehmen" }
    assert_selector "trix-editor", text: "Projektwebsite"
    assert_no_selector "trix-editor", text: "Anderer Text"
    fill_in "Anzeigetext", with: ""
    fill_in "Linkadresse", with: "example.de"
    find_field("Anzeigetext").send_keys(:enter)
    assert_selector "trix-editor a[href='https://example.de']", exact_text: "https://example.de"
    assert_equal "https://example.de", editor.text
  end

  test "Links lassen sich ueber die Werkzeugleiste entfernen" do
    editor = find("trix-editor")
    editor.click
    editor.send_keys("Projektwebsite")
    editor.evaluate_script("this.editor.setSelectedRange([0, 14])")
    within(".rich-text__toolbar") { click_button "Link" }
    find(".rich-text__link-dialog[data-trix-active] input[name=href]").set("https://example.de")
    page.save_screenshot(Rails.root.join("tmp/screenshots/action-text-link-desktop-open.png"))
    within(".rich-text__link-dialog[data-trix-active]") { click_button "Übernehmen" }
    assert_selector "trix-editor a"
    editor.evaluate_script("this.editor.setSelectedRange([1, 1])")
    within(".rich-text__toolbar") { click_button "Link" }
    within(".rich-text__link-dialog[data-trix-active]") { click_button "Entfernen" }
    assert_no_selector "trix-editor a"
    assert_selector "trix-editor", text: "Projektwebsite"
  end

  test "Action Text funktioniert in neuen Positionen und beim Leeren" do
    fill_invoice
    click_button "Position hinzufügen"
    editors = all("trix-editor")
    assert_equal 2, editors.length
    assert_equal 2, editors.map { |editor| editor[:input] }.uniq.length
    assert_equal 2, editors.map { |editor| editor[:toolbar] }.uniq.length
    second = editors.last
    second.click
    second.send_keys("Zweite Beschreibung")
    assert_selector "trix-editor", text: "Zweite Beschreibung"
    within all(".invoice-line").last do
      click_button "Position löschen"
    end
    first = find("trix-editor")
    first.click
    first.send_keys("Erste Beschreibung")
    within(".invoice-line") { click_button "Position leeren" }
    assert_equal "", find("input[name*='[details]']", visible: :all).value.gsub(/<[^>]+>/, "").strip
    assert_equal "", first.text
    first.click
    first.send_keys("Neue Beschreibung")
    assert_selector "trix-editor", text: "Neue Beschreibung"
  end

  test "Action Text blockiert Dateien Bilder und fremde HTML Formatierung" do
    editor = find("trix-editor.rich-text__editor")
    assert editor.evaluate_script(<<~JS)
      (() => {
        let rejected = false;
        this.addEventListener('trix-file-accept', event => { rejected = event.defaultPrevented }, { once: true });
        this.editor.insertFile(new File(['test'], 'bild.png', { type: 'image/png' }));
        return rejected;
      })()
    JS
    editor.evaluate_script(<<~JS)
      (() => {
        const data = new DataTransfer();
        data.setData('text/plain', 'Nur dieser Text');
        data.setData('text/html', '<div><img src="https://example.invalid/bild.png"><strong>Fremder Text</strong></div>');
        this.dispatchEvent(new ClipboardEvent('paste', { clipboardData: data, bubbles: true, cancelable: true }));
      })()
    JS
    assert_selector "trix-editor", text: "Nur dieser Text"
    assert_no_selector "trix-editor img, trix-editor figure, trix-editor strong"
    assert_no_match(/attachment|img|Fremder Text/, find("input[name*='[details]']", visible: :all).value)
  end

  test "einfache Textlisten werden im Beschreibungseditor als Liste formatiert" do
    assert_selector ".rich-text__editor", visible: true
    fill_invoice
    click_link "Später"
    assert_current_path invoices_path
    draft = InvoiceDraft.active.sole
    data = draft.data.deep_dup
    data["invoice_lines_attributes"]["0"]["details"] = "Einleitung\n- Update Divi 4.27.8\n- Update WPRocket"
    draft.update!(data: data)
    visit edit_draft_invoices_path(draft_id: draft.id)

    within ".rich-text__editor" do
      assert_text "Einleitung"
      assert_selector "ul > li", count: 2
      assert_text "Update Divi 4.27.8"
      assert_text "Update WPRocket"
    end
  end

  test "Positionstitel nutzt die Breite ohne unnoetigen Umbruch" do
    page.current_window.resize_to(1400, 1100)
    fill_invoice
    choose "Anzahlungsrechnung"
    # Systemschriften unterscheiden sich unter Linux und macOS; der Titel muss in beiden Fällen hineinpassen.
    fill_in line_id("description"), with: "Teilnehmermanagement anpassen"
    click_button "Vorschau"
    within_frame("invoice-preview-frame") do
      assert_selector ".invoice-pages:not(.invoice-pages--rendering) .invoice-position-row"
      cell = find(".invoice-pages .invoice-position-row td:first-child")
      assert_equal "1. Teilnehmermanagement anpassen", cell.text
      assert_equal 1, cell.evaluate_script("(() => { const range = document.createRange(); range.selectNodeContents(this); return range.getClientRects().length; })()")
      page.save_screenshot(Rails.root.join("tmp/screenshots/invoice-position-title-width.png"))
    end
  end

  test "Rechnungsvorschau zeigt keinen Strich zwischen Positionstitel und Beschreibung" do
    fill_invoice
    assert_selector ".rich-text__editor", visible: true
    editor = find(".rich-text__editor")
    editor.set("Erste Zeile\nZweite Zeile")
    click_button "Vorschau"
    assert_selector "dialog.invoice-preview-dialog[open]"
    within_frame("invoice-preview-frame") do
      position = find(".invoice-position-row--has-description")
      description = position.find(:xpath, "following-sibling::tr[contains(@class, 'invoice-description-row')][1]")
      assert_equal "0px", position.all("td").first.evaluate_script("getComputedStyle(this).borderBottomWidth")
      assert_equal "2px", position.all("td").first.evaluate_script("getComputedStyle(this).paddingBottom")
      assert_equal 1, description.all("td").length
      assert_equal "0px", description.find(".invoice-line-details > :first-child").evaluate_script("getComputedStyle(this).marginTop")
    end
  end

  test "Bindestriche in eingegebenen Beschreibungszeilen werden direkt zu Listenpunkten" do
    assert_selector ".rich-text__editor", visible: true
    editor = find(".rich-text__editor")
    editor.click
    editor.send_keys("- ", "Erster Punkt", :enter, "Zweiter Punkt")

    within ".rich-text__editor" do
      assert_selector "ul > li", count: 2
      assert_text "Erster Punkt"
      assert_text "Zweiter Punkt"
      assert_no_text "- Erster Punkt"
    end
    assert_no_match(/<p>\s*[-–—]/, find("input[name*='[details]']", visible: :all).value)
    assert_equal "0px", find(".rich-text__editor li + li", visible: :all).evaluate_script("getComputedStyle(this).marginTop")
  end

  test "Listen beginnen in der ersten Zeile sofort und behalten den Cursor beim Weiterschreiben" do
    resize_browser(390, 844)
    editor = find(".rich-text__editor")
    editor.click
    editor.send_keys("- ")
    assert_selector ".rich-text__editor ul > li", count: 1
    editor.send_keys("Unterstützung mehrere Projekte")
    assert_selector ".rich-text__editor li", exact_text: "Unterstützung mehrere Projekte"
    editor.send_keys(:enter, "Weiteres Projekt")
    assert_selector ".rich-text__editor ul > li", count: 2
    assert_equal [ "Unterstützung mehrere Projekte", "Weiteres Projekt" ], editor.all("li").map(&:text)
    assert editor.evaluate_script("window.getSelection().anchorNode.parentElement.closest('li') === this.querySelector('li:last-child')")
    assert_equal "Weiteres Projekt".length, editor.evaluate_script("window.getSelection().anchorOffset")
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.current_window.resize_to(1400, 1100)
  end

  test "Listen nach einem Absatz behalten Text Formatierung und Cursor" do
    editor = find(".rich-text__editor")
    editor.click
    editor.send_keys("Einleitung")
    assert_equal "Einleitung\n", editor.evaluate_script("this.editor.getDocument().toString()")
    editor.send_keys(:enter)
    assert_equal "Einleitung\n\n", editor.evaluate_script("this.editor.getDocument().toString()")
    assert_selector ".rich-text__editor" do |field|
      field.evaluate_script("JSON.stringify(this.editor.getSelectedRange())") == "[11,11]"
    end
    editor.send_keys("- ")
    assert_selector ".rich-text__editor li", count: 1
    editor.send_keys("Erster Punkt")
    editor.send_keys(:enter)
    editor.send_keys("Zweiter Punkt")
    assert_selector ".rich-text__editor", text: "Einleitung"
    assert_equal [ "Erster Punkt", "Zweiter Punkt" ], editor.all("li").map(&:text), editor.evaluate_script("JSON.stringify({html: this.innerHTML, text: this.editor.getDocument().toString(), range: this.editor.getSelectedRange()})")
    assert_equal "Zweiter Punkt".length, editor.evaluate_script("window.getSelection().anchorOffset")
  end

  test "Cursor bleibt beim Bearbeiten der Positionsbeschreibung an der Eingabeposition" do
    assert_selector ".rich-text__editor", visible: true
    editor = find(".rich-text__editor")
    editor.click
    editor.send_keys("Beschreibungstext")

    assert_equal "Beschreibungstext", editor.text
    assert_equal "Beschreibungstext".length, editor.evaluate_script("window.getSelection().anchorOffset")
    assert page.evaluate_script("document.activeElement.matches('.rich-text__editor')")
  end

  test "eigene Angaben lassen sich ueber Details ein- und ausklappen und werden aktualisiert" do
    assert_no_selector ".invoice-seller-summary", visible: true
    assert_selector ".invoice-seller-edit-label", text: "Bearbeitung schließen"
    fill_in "invoice_seller_name", with: "Neuer Name"
    fill_in "invoice_seller_street", with: "Neue Straße 9"
    fill_in "invoice_seller_tax_identifier", with: "99/888/77777"
    find(".invoice-seller-details > summary").click
    assert_no_selector ".invoice-seller-details[open]"
    within ".invoice-seller-summary" do
      assert_text "Neuer Name"
      assert_text "Neue Straße 9"
      assert_text "99/888/77777"
    end
    assert_selector ".invoice-seller-summary__action"
    positions = page.evaluate_script <<~JS
      (() => {
        const details = document.querySelector(".invoice-seller-details");
        const data = details.querySelector(".invoice-seller-summary").getBoundingClientRect();
        const action = details.querySelector(".invoice-seller-summary__action").getBoundingClientRect();
        return { dataTop: data.top, dataBottom: data.bottom, actionTop: action.top, actionBottom: action.bottom, actionLeft: action.left, dataRight: data.right };
      })()
    JS
    assert_operator positions.fetch("actionTop"), :>=, positions.fetch("dataTop")
    assert_operator positions.fetch("actionBottom"), :<=, positions.fetch("dataBottom")
    assert_operator positions.fetch("actionLeft"), :>=, positions.fetch("dataRight")
    assert_selector ".invoice-seller-summary__action svg"
    assert_selector "input#invoice_seller_name", visible: false
    find(".invoice-seller-details > summary").click
    assert_selector ".invoice-seller-details[open]"
    assert_no_selector ".invoice-seller-summary", visible: true
    assert_selector "input#invoice_seller_name", visible: true
  end

  test "Bar bezahlte Rechnung zeigt keinen offenen Zahlungsauftrag" do
    fill_invoice
    select "Barzahlung", from: "Zahlungsart"
    check "Bereits vollständig bezahlt"
    fill_in "Datum des Zahlungseingangs", with: (Date.current - 1).strftime("%d.%m.%Y")
    select "Privatkonto", from: "Geld erhalten auf"
    click_button "Festschreiben"
    assert_selector ".invoice-pages:not(.invoice-pages--rendering) .invoice-payment", text: "Bereits vollständig bezahlt (bar)."
    payment = Invoice.order(:id).last.payment_entry
    assert_equal Date.current - 1, payment.paid_on
    assert_equal "private", payment.payment_account
    assert_equal Invoice.order(:id).last.total, payment.amount
    assert_no_selector ".invoice-pages .invoice-payment", text: "Offener Betrag:"
    assert_no_selector ".invoice-pages .invoice-payment", text: "Bitte den Betrag bis zum"
    page.save_screenshot(Rails.root.join("tmp/screenshots/invoice-cash-paid.png"))
  end

  test "Hinweisbox bleibt sichtbar und Aktionen stehen in der gewuenschten Reihenfolge" do
    fill_invoice
    click_button "Festschreiben"
    assert_selector ".print-invoice h1"
    assert_selector ".invoice-action-hints", text: "E-Rechnung:"
    assert_selector ".invoice-action-hints", text: "Fehler auf der Rechnung?"
    actions = all(".invoice-actions .button").map(&:text)
    assert_equal [ "Alle Rechnungen", "Drucken oder als PDF speichern", "XRechnung herunterladen (XML)" ], actions
    assert_selector ".invoice-correction-hint form[data-turbo-confirm] button", text: "Rechnung stornieren und korrigieren"
    page.refresh
    assert_selector ".invoice-action-hints", text: "E-Rechnung:"
    assert_selector ".invoice-action-hints", text: "Fehler auf der Rechnung?"
  end

  test "Kundenaenderungen werden erst vor Vorschau oder Festschreiben abgefragt" do
    fill_invoice
    click_button "Festschreiben"
    assert_selector ".print-invoice h1"
    visit new_invoice_path
    fill_in "invoice_buyer_name", with: "Testkunde"
    find("#customer-name-suggestions li", text: "Testkunde GmbH, Berlin").click
    select "Stunde", from: line_id("unit_code")
    fill_in "Individueller Stundensatz", with: "40"
    fill_in line_id("description"), with: "Beratung"
    assert_no_selector ".customer-update-choice"
    windows_before = page.driver.browser.window_handles.size
    click_button "Vorschau"
    within ".customer-update-choice" do
      assert_text "Individueller Stundensatz: nicht hinterlegt → 40,00"
      assert_selector "li", count: 1
    end
    assert_equal windows_before, page.driver.browser.window_handles.size
    within("dialog[open]") { click_button "Abbrechen" }
    assert_no_selector "dialog[open]"
    assert_no_selector ".customer-update-choice"
    resize_browser(390, 1100)
    click_button "Vorschau"
    assert_selector "dialog[open]"
    assert_no_horizontal_overflow
    page.save_screenshot(Rails.root.join("tmp/screenshots/customer-update-dialog-mobile.png"))
    choose "Nur für diese Rechnung verwenden"
    click_button "Weiter zur Vorschau"
    assert_selector "dialog.invoice-preview-dialog[open]"
    within_frame("invoice-preview-frame") { assert_selector ".print-invoice" }
    assert_nil Customer.find_by!(name: "Testkunde GmbH").hourly_rate
  end

  test "Empfaenger steht im festen Fensteranschriftfeld der A4 Vorschau" do
    fill_invoice
    fill_in "Rechnungstitel (optional)", with: "Website-Betreuung Oktober 2026"
    fill_in "invoice_seller_phone", with: "+49 151 522 09 807"
    fill_in "invoice_buyer_contact_name", with: "Bernd Hellmann"
    click_button "Festschreiben"
    assert_selector ".invoice-pages:not(.invoice-pages--rendering) .pagedjs_page"
    assert_selector ".invoice-pages .print-invoice__subject", text: "Website-Betreuung Oktober 2026"
    measurements = page.evaluate_script <<~JS
      (() => {
        const sheet = document.querySelector('.invoice-pages .pagedjs_page');
        const page = sheet.getBoundingClientRect();
        const address = sheet.querySelector('.print-invoice__recipient-address').getBoundingClientRect();
        const title = sheet.querySelector('.print-invoice__title').getBoundingClientRect();
        const mm = px => px * 25.4 / 96;
        return { left: mm(address.left - page.left), top: mm(address.top - page.top), bottom: mm(address.bottom - page.top), width: mm(address.width), title: mm(title.top - page.top) };
      })()
    JS
    assert_in_delta 25, measurements.fetch("left"), 0.5
    assert_in_delta 62.7, measurements.fetch("top"), 0.5
    assert_in_delta 80, measurements.fetch("width"), 0.5
    assert_operator measurements.fetch("bottom"), :<=, 90
    assert_operator measurements.fetch("title"), :>, measurements.fetch("bottom")
    resize_browser(1400, 1400)
    sheet = find(".invoice-pages .pagedjs_page")
    page.execute_script("arguments[0].scrollIntoView({block: 'start', behavior: 'instant'})", sheet)
    sheet.native.save_screenshot(Rails.root.join("tmp/screenshots/invoice-window-envelope.png"))
  end

  test "Naechste fortlaufende Nummer erscheint auch bei fehlendem Kundenkuerzel" do
    fill_invoice
    find("#invoice-number-preview").click
    find('.invoice-number-template[data-format="[Rechnungsart]-[Jahr]-[Fortlaufendenummer]-[Kundenkürzel]"]').click
    assert_selector "#invoice-number-format-preview", text: "Bitte ergänze das Kundenkürzel", exact_text: true
    assert_selector ".invoice-number-preview", text: "Vorschau: Bitte ergänze das Kundenkürzel"
    assert_no_selector "[data-invoice-number-target=editorStatus]"
    fill_in "Zuletzt verwendete fortlaufende Nummer", with: "1000"
    assert_text "Nächste fortlaufende Nummer: 1001"
    assert_no_text "Nächste fortlaufende Nummer: wird ermittelt"
    find("#invoice-number-format-preview a", text: "Kundenkürzel").click
    assert_selector "#invoice-number-editor[open]"
    assert_equal "invoice-number-abbreviation-editor", page.evaluate_script("document.activeElement.id")
    fill_in "invoice-number-abbreviation-editor", with: "MF"
    assert_selector "#invoice-number-format-preview", text: "RE-#{Date.current.year}-1001-MF"
    assert_selector ".invoice-number-preview", text: "Vorschau: RE-#{Date.current.year}-1001-MF"
    find("[aria-label='Bearbeitung der Rechnungsnummer schließen']").click
    assert_field "invoice_buyer_abbreviation", with: "MF"
    find("#invoice-number-preview").click
    assert_field "invoice-number-abbreviation-editor", with: "MF"
    assert_text "Nächste fortlaufende Nummer: 1001"
    assert_field "Zuletzt verwendete fortlaufende Nummer", with: "1000"
    find("[aria-label='Bearbeitung der Rechnungsnummer schließen']").click
    click_button "Festschreiben"
    assert_selector ".print-invoice h1", text: "RE-#{Date.current.year}-1001-MF"
  end

  test "Nummerierung anpassen berechnet aus der letzten Nummer die naechste fuer das Rechnungsjahr" do
    fill_invoice
    find("#invoice-number-preview").click
    find('.invoice-number-template[data-format="[Jahr]-[Monat]-[Tag]-[Fortlaufendenummer]"]').click
    assert_field "Zuletzt verwendete fortlaufende Nummer"
    fill_in "Zuletzt verwendete fortlaufende Nummer", with: "147"
    assert_text "Nächste fortlaufende Nummer: 148"
    last_number = find("#invoice_invoice_number_last")
    last_number.send_keys(:end, :backspace, :backspace, :backspace)
    assert_text "Nächste fortlaufende Nummer: 1"
    assert_field "Zuletzt verwendete fortlaufende Nummer", with: ""
    last_number.send_keys("147")
    assert_text "Nächste fortlaufende Nummer: 148"
    assert_field "Zuletzt verwendete fortlaufende Nummer", with: "147"
    find("[aria-label='Bearbeitung der Rechnungsnummer schließen']").click
    click_button "Festschreiben"
    assert_selector ".print-invoice h1", text: "#{Date.current.iso8601}-0148"
    visit new_invoice_path
    find("#invoice-number-preview").click
    assert_field "Zuletzt verwendete fortlaufende Nummer", with: "148"
    fill_in "Zuletzt verwendete fortlaufende Nummer", with: "100"
    assert_text "Gib mindestens diese Nummer ein."
    fill_in "Zuletzt verwendete fortlaufende Nummer", with: "148"
    assert_text "Nächste fortlaufende Nummer: 149"
    find("[aria-label='Bearbeitung der Rechnungsnummer schließen']").click
    fill_in "invoice_issued_on_display", with: "01.01.2027"
    find("#invoice-number-preview").click
    assert_selector "[data-invoice-number-target=counterYear]", text: "2027"
    assert_field "Zuletzt verwendete fortlaufende Nummer", with: "0"
    assert_text "Nächste fortlaufende Nummer: 1"
  end

  test "Positionspreise verwenden deutsche Dezimalzahlen auch nach dem Speichern" do
    fill_invoice
    select "Stunde", from: line_id("unit_code")
    fill_in line_id("quantity"), with: "2"
    fill_in line_id("unit_price"), with: "50,50"
    find("#invoice-step-lines").click
    assert_field line_id("unit_price"), with: "50,50"
    assert_text "Summe der Position: 101,00"
    click_button "Festschreiben"
    assert_selector ".print-invoice"
    assert_equal BigDecimal("101"), Invoice.last.total
    assert_equal BigDecimal("50.50"), Invoice.last.invoice_lines.first.unit_price
    visit new_invoice_path(copy_from: Invoice.last.id)
    assert_field line_id("unit_price"), with: "50,50"
    select "Pauschal", from: line_id("unit_code")
    fill_in line_id("unit_price"), with: "50"
    find("#invoice-step-lines").click
    assert_field line_id("unit_price"), with: "50,00"
    assert_text "Summe der Position: 50,00"
  end

  test "Rechenwege direkt in Menge und Preis werden ohne Dialog uebernommen" do
    within first(".invoice-line") do
      select "Stück", from: line_id("unit_code")
      fill_in line_id("quantity"), with: "2 + 3"
      assert_selector ".inline-calculation-result", text: "Ergebnis: 5"
      assert_field line_id("quantity"), with: "2 + 3"
      find_field(line_id("quantity")).send_keys(:enter)
      assert_field line_id("quantity"), with: "5"
      fill_in line_id("unit_price"), with: "800 / 2"
      assert_selector ".inline-calculation-result", text: "Ergebnis: 400,00"
      assert_field line_id("unit_price"), with: "800 / 2"
      fill_in line_id("unit_price"), with: "800 /"
      assert_no_selector ".inline-calculation-result", text: "Ergebnis: 400,00"
      fill_in line_id("unit_price"), with: "800 / 2"
      find_field(line_id("quantity")).click
      assert_field line_id("unit_price"), with: "400,00"
      assert_text "Summe der Position: 2.000,00"
      fill_in line_id("quantity"), with: "1,5"
      find_field(line_id("unit_price")).click
      assert_field line_id("quantity"), with: "1.5"
      fill_in line_id("unit_price"), with: "10 / 0"
      find_field(line_id("unit_price")).send_keys(:enter)
      assert_field line_id("unit_price"), with: "10 / 0"
      assert_match "gültigen Wert", find_field(line_id("unit_price")).evaluate_script("this.validationMessage")
      assert_no_selector "dialog[open]"
    end
  end

  test "Direkte Berechnung funktioniert fuer alle Einheiten ohne Rechnerbutton" do
    within first(".invoice-line") do
      %w[Stück Stunde Tag Monat].each do |unit|
        select unit, from: line_id("unit_code")
        assert_no_button "Rechner öffnen"
        assert_text "Kommazahlen und Rechenwege sind möglich"
        fill_in line_id("quantity"), with: "2 + 3 * 4"
        find_field(line_id("quantity")).send_keys(:enter)
        assert_field line_id("quantity"), with: "14"
      end
      select "Pauschal", from: line_id("unit_code")
      assert_no_button "Rechner öffnen"
      assert_text "Rechenwege sind möglich, z. B. 800 / 2."
      fill_in line_id("unit_price"), with: "(20 min + 20 min + 1,5 Std + 1:30) * 60"
      find_field(line_id("unit_price")).send_keys(:enter)
      assert_field line_id("unit_price"), with: "220,00"
      assert_text "Summe der Position: 220,00"
    end
  end

  setup do
    visit new_invoice_path
    assert_selector ".date-picker--enhanced", count: 6, visible: :all
    assert_no_selector "input[name='invoice[tax_mode]']"
    assert_no_selector "select[name$='[tax_rate]']"
    # Address suggestions are an external service; these scenarios exercise manual entry.
    page.execute_script <<~JS
      const originalFetch = window.fetch;
      window.fetch = (url, options) => String(url).startsWith('https://photon.')
        ? Promise.resolve(new Response(JSON.stringify({ features: [] }), { status: 200 }))
        : originalFetch(url, options);
    JS
  end

  teardown do
    errors = page.driver.browser.logs.get(:browser).select do |entry|
      entry.message.match?(/Uncaught|Error invoking action|Error connecting controller/)
    end
    assert_empty errors.map(&:message), "JavaScript-Fehler im Browser"
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "ausgewaehlter Kunde kann umbenannt oder nur fuer eine Rechnung geaendert werden" do
    fill_invoice
    click_button "Festschreiben"
    assert_selector ".print-invoice"
    original = Invoice.last
    customer = original.customer
    visit new_invoice_path
    fill_in "invoice_buyer_name", with: "testkunde"
    assert_selector "#customer-name-suggestions", text: "Testkunde GmbH, Berlin"
    assert_no_selector "#customer-name-suggestions", text: "Anderer Kunde"
    [ 390, 1400 ].each do |width|
      resize_browser(width, 1100)
      suggestion_gap = page.evaluate_script(<<~JS)
        document.getElementById('customer-name-suggestions').getBoundingClientRect().top -
          document.getElementById('invoice_buyer_name').getBoundingClientRect().bottom
      JS
      assert_in_delta 4, suggestion_gap, 1
    end
    find("#customer-name-suggestions li", text: "Testkunde GmbH, Berlin").click
    assert_field "invoice_buyer_name", with: "Testkunde GmbH"
    assert_no_selector "#customer-name-suggestions"
    assert_no_selector ".customer-update-choice"
    fill_in "invoice_buyer_name", with: "Musterfirma Neu"
    assert_no_selector ".customer-update-choice"
    fill_in line_id("description"), with: "Neue Beratung"
    fill_in line_id("unit_price"), with: "50"
    click_button "Festschreiben"
    assert_selector "dialog[open].customer-update-dialog"
    assert_selector "dialog[open].customer-update-dialog [data-customer-select-target=continueButton] > svg.button-icon[aria-hidden=true]"
    choose "Nur für diese Rechnung verwenden"
    assert_selector "[data-invoice-draft-target=status]", text: "Entwurf gespeichert"
    page.refresh
    assert_field "customer-select", with: customer.id.to_s, visible: :all
    assert_checked_field "Nur für diese Rechnung verwenden", visible: :all
    assert_field "invoice_buyer_name", with: "Musterfirma Neu"
    click_button "Festschreiben"
    within("dialog[open]") { click_button "Festschreiben" }
    assert_selector ".print-invoice", text: "Musterfirma Neu"
    assert_equal customer.id, Invoice.last.customer_id
    assert_equal "Testkunde GmbH", customer.reload.name
    visit new_invoice_path
    fill_in "invoice_buyer_name", with: "Testkunde"
    find("#customer-name-suggestions li", text: "Testkunde GmbH, Berlin").click
    fill_in "invoice_buyer_name", with: "Musterfirma Neu"
    fill_in line_id("description"), with: "Neue Beratung"
    fill_in line_id("unit_price"), with: "50"
    click_button "Festschreiben"
    choose "Als Vorgabe für diesen Kunden speichern"
    within("dialog[open]") { click_button "Festschreiben" }
    assert_selector ".print-invoice", text: "Musterfirma Neu"
    assert_equal customer.id, Invoice.last.customer_id
    assert_equal "Musterfirma Neu", customer.reload.name
    assert_equal "Testkunde GmbH", original.reload.buyer_name
    assert_equal 1, customer.workspace.customers.count
  end

  test "Popup-Formatfeld bleibt beim Bearbeiten und bei Validierungsfehlern sichtbar" do
    fill_invoice
    [ 1400, 390 ].each do |width|
      resize_browser(width, 1100)
      find("#invoice-number-preview").click
      assert_field "invoice-number-preview", with: "RE-#{Date.current.year}-0001"
      positions = []
      [ [ "RE-[Jahr]-[Fortlaufendenummer]", "RE-#{Date.current.year}-0001" ],
        [ "MF-[Jahr]-[Monat]-[Tag]", "MF-#{Date.current.iso8601}" ],
        [ "MF-[Jahr]-[Fortlaufende", "MF-#{Date.current.year}-[Fortlaufende" ],
        [ "#{'R' * 70}-[Fortlaufendenummer]", "#{'R' * 70}-0001" ],
        [ InvoiceNumber::DEFAULT_FORMAT, "RE-#{Date.current.year}-0001" ] ].each do |format, preview|
        find("#invoice-number-format-editor").set(format)
        assert_field "invoice-number-preview", with: preview
        assert_selector "#invoice-number-format-preview", text: preview, exact_text: true
        unless format.include?("[Fortlaufendenummer]")
          assert_selector "[data-invoice-number-target=collisionHint]", text: "Dein Format kann zu doppelten Rechnungsnummern führen. Bei einer doppelten Rechnungsnummer wird die App automatisch -02, -03 usw. anhängen, sodass eine doppelte Rechnungsnummer nicht entsteht."
          assert_selector ".invoice-number-preview + .invoice-status[role=status]", text: "Dein Format kann zu doppelten Rechnungsnummern führen."
        end
        assert_selector "#invoice-format-help", visible: :visible
        positions << page.evaluate_script("document.querySelector('#invoice-number-format-editor').getBoundingClientRect().top - document.querySelector('.invoice-number-editor').getBoundingClientRect().top")
      end
      assert_operator positions.max - positions.min, :<=, 1, "Editor bewegt sich bei #{width}px: #{positions.inspect}"
      find("#invoice-number-format-editor").send_keys(:escape)
      assert_selector "#invoice-number-editor:not([open])", visible: :all
    end
  end

  test "Textmarkierung darf ausserhalb des Popups enden ohne es zu schliessen" do
    [ 1400, 390 ].each do |width|
      resize_browser(width, 1100)
      find("#invoice-number-preview").click
      field = find("#invoice-number-format-editor")
      format = field.value
      page.driver.browser.action.move_to(field.native).click_and_hold.move_to_location(5, 10).release.perform
      assert_selector "#invoice-number-editor[open]"
      assert_field "invoice-number-format-editor", with: format
      assert field.evaluate_script("this.selectionStart < this.selectionEnd"), "Text wurde nicht markiert"
      page.driver.browser.action.move_to_location(5, 10).click.perform
      assert_no_selector "#invoice-number-editor[open]"
    end
  end

  test "Rechnungsnummer wird im Popup bearbeitet und zeigt Vorlagen auch mobil" do
    fill_invoice
    assert_selector "#invoice-number-editor:not([open])", visible: :all
    assert_no_selector ".invoice-number-template"
    assert_no_selector ".invoice-number-result"
    find("#invoice-number-preview").click
    assert_selector "#invoice-number-editor[open]"
    assert_selector "#invoice-number-preview[aria-expanded=true][aria-haspopup=dialog]"
    assert_operator find(".invoice-number-preview").evaluate_script("parseFloat(getComputedStyle(this).fontSize)"), :>=, 17
    assert page.evaluate_script("document.querySelector('#invoice-number-editor').matches(':modal')")
    assert_no_text "Beim Erstellen wird das Format standardmäßig als Vorgabe für zukünftige Rechnungen gespeichert."
    assert_no_text "Empfohlen: Rechnungsart, Jahr und fortlaufende Nummer. Die App zählt deine Rechnungen automatisch"
    assert_unchecked_field "Anpassungen nur für diese Rechnung verwenden"
    assert_selector "#invoice-number-adjustment-title", text: "Nummerierung anpassen"
    assert_no_selector ".invoice-number-editor__footer"
    assert_no_selector ".invoice-number-editor button", text: "Fertig"
    within ".invoice-number-editor" do
      assert_selector ".invoice-number-template", count: 5
      assert_selector ".invoice-number-template[aria-pressed=true] code", text: InvoiceNumber::DEFAULT_FORMAT
      assert_text "Beispiel: #{Date.current.iso8601}-0001"
      assert_text "Beispiel: MF-#{Date.current.iso8601}"
      assert_no_selector "button[data-token='[Mehrfachrechnungszähler]']"
      find('.invoice-number-template[data-format="[Rechnungsart]-[Jahr]-[Fortlaufendenummer]"]').click
      assert_selector ".invoice-number-template[aria-pressed=true]", text: InvoiceNumber::DEFAULT_FORMAT
      find("[aria-label='Bearbeitung der Rechnungsnummer schließen']").click
    end
    assert_selector "#invoice-number-editor:not([open])", visible: :all
    assert_field "invoice-number-preview", with: "RE-#{Date.current.year}-0001"
    find("#invoice-number-preview").send_keys(:enter)
    assert_selector "#invoice-number-editor[open]"
    find("#invoice-number-format-editor").send_keys(:escape)
    assert_selector "#invoice-number-editor:not([open])", visible: :all
    assert_equal "invoice-number-preview", page.evaluate_script("document.activeElement.id")
    find("#invoice-number-preview").send_keys("X")
    assert_selector "#invoice-number-editor[open]"
    find("#invoice-number-format-editor").send_keys(:escape)
    assert_field "invoice-number-preview", with: "RE-#{Date.current.year}-0001"
    resize_browser(390, 844)
    find("#invoice-number-preview").click
    assert_equal true, find("#invoice-number-editor").evaluate_script("this.scrollWidth <= this.clientWidth")
    assert_equal true, page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    page.save_screenshot(Rails.root.join("tmp/screenshots/number-formatter-mobile.png"))
    find("#invoice-number-editor-title").click
    assert_selector "#invoice-number-editor[open]"
    page.driver.browser.action.move_to_location(5, 10).click.perform
    assert_no_selector "#invoice-number-editor[open]"
    assert_equal "invoice-number-preview", page.evaluate_script("document.activeElement.id")
    find("#invoice-number-preview").click
    assert_field "invoice-number-format-editor", with: InvoiceNumber::DEFAULT_FORMAT
    resize_browser(1400, 1100)
    page.save_screenshot(Rails.root.join("tmp/screenshots/number-formatter-desktop.png"))
    page.driver.browser.action.move_to_location(5, 10).click.perform
    assert_selector "#invoice-number-editor:not([open])", visible: :all
    find("#invoice-number-preview").click
    previous_number = find("#invoice-number-preview").value
    find("#invoice-number-format-editor").set("X" * 81)
    assert_selector "[data-invoice-number-target=editorStatus]", text: "Rechnungsnummernformat ist zu lang"
    assert_equal previous_number, find("#invoice-number-preview").value
    assert_no_selector "[data-invoice-number-target=status]:not([hidden])"
    assert_selector "[data-invoice-number-target=editorStatus]", text: "Rechnungsnummernformat ist zu lang"
    assert_selector "#invoice-number-editor[open]"
    assert_equal "grid", find("[aria-label='Bearbeitung der Rechnungsnummer schließen']").evaluate_script("getComputedStyle(this).display")
    assert_equal "24px", find("[aria-label='Bearbeitung der Rechnungsnummer schließen']").evaluate_script("getComputedStyle(this).lineHeight")
    find("[aria-label='Bearbeitung der Rechnungsnummer schließen']").click
    click_button "Festschreiben"
    assert_selector "#invoice-number-editor[open]"
    assert_equal "invoice-number-format-editor", page.evaluate_script("document.activeElement.id")
  end

  test "Rechnungsart aktualisiert Nummer und Vorlagen und wird beim Storno zu ST" do
    fill_invoice
    assert_selector "#billing-kind-cards legend", text: "Rechnungsart"
    choose "Anzahlungsrechnung"
    fill_in "Rechnungstitel (optional)", with: "App Anpassungen"
    assert_field "invoice-number-preview", with: "ANZ-#{Date.current.year}-0001"
    resize_browser(390, 844)
    find("#invoice-number-preview").click
    assert_selector "button[data-token='[Rechnungsart]']", text: "Rechnung=RE, Anzahlung=ANZ, Abschlag=ABS, Schlussrechnung=SR, Storno=ST, Angebot=AN, Auftrag=AU"
    assert_selector ".invoice-number-template[data-format='[Rechnungsart]-[Jahr]-[Fortlaufendenummer]']", text: "Beispiel: ANZ-#{Date.current.year}-0001"
    field = find("#invoice-number-format-editor")
    field.set("-[Jahr]-[Fortlaufendenummer]")
    page.execute_script("arguments[0].focus(); arguments[0].setSelectionRange(0, 0)", field)
    find("button[data-token='[Rechnungsart]']").click
    assert_field "invoice-number-format-editor", with: InvoiceNumber::DEFAULT_FORMAT
    assert_selector "#invoice-number-format-preview", text: "ANZ-#{Date.current.year}-0001"
    assert_no_horizontal_overflow
    find("[aria-label='Bearbeitung der Rechnungsnummer schließen']").click
    choose "Abschlagsrechnung"
    assert_field "invoice-number-preview", with: "ABS-#{Date.current.year}-0001"
    choose "invoice_billing_kind_regular"
    assert_field "invoice-number-preview", with: "RE-#{Date.current.year}-0001"
    choose "Anzahlungsrechnung"
    click_button "Festschreiben"
    assert_selector ".print-invoice__title h1", text: "ANZ-#{Date.current.year}-0001", visible: :all
    original = Invoice.order(:id).last
    accept_confirm { click_button "Rechnung stornieren und korrigieren" }
    assert_selector "h1", text: "Korrekturrechnung erstellen"
    assert_equal "ST-#{Date.current.year}-0002", original.reload.cancellation.invoice_number
    assert_equal InvoiceNumber::DEFAULT_FORMAT, original.cancellation.invoice_number_format
  end

  test "Platzhalterkarten zeigen ihre Erklaerungen und sind per Tastatur und Touch bedienbar" do
    resize_browser(1400, 1100)
    find("#invoice-number-preview").click
    assert_selector ".invoice-number-token__description", count: 7
    assert_no_selector "[role=tooltip]", visible: :all
    assert_selector "button[data-token='[Jahr]']", text: "Jahr des Dokumentdatums, z.B. 2026."
    field = find("#invoice-number-format-editor")
    field.set("-[Jahr]-[Fortlaufendenummer]")
    page.execute_script("arguments[0].focus(); arguments[0].setSelectionRange(0, 0)", field)
    field.send_keys(:tab)
    assert_selector "[data-invoice-number-target=resetFormat]:focus"
    page.driver.browser.action.send_keys(:tab).perform
    assert_equal "[Rechnungsart]", page.evaluate_script("document.activeElement.dataset.token")
    page.driver.browser.action.send_keys(:enter).perform
    assert_field "invoice-number-format-editor", with: InvoiceNumber::DEFAULT_FORMAT
    assert_selector "#invoice-number-format-preview", text: "RE-#{Date.current.year}-0001"
    page.save_screenshot(Rails.root.join("tmp/screenshots/invoice-token-cards-desktop.png"))
    resize_browser(390, 844)
    field.set("RE--[Fortlaufendenummer]")
    page.execute_script("arguments[0].focus(); arguments[0].setSelectionRange(3, 3)", field)
    month = find("button[data-token='[Monat]'] .invoice-number-token__description")
    page.execute_script("arguments[0].scrollIntoView({behavior: 'instant', block: 'center'})", month)
    x, y = month.evaluate_script("[this.getBoundingClientRect().x + this.clientWidth / 2, this.getBoundingClientRect().y + this.clientHeight / 2]")
    page.driver.browser.execute_cdp("Input.dispatchTouchEvent", type: "touchStart", touchPoints: [ { x: x, y: y } ])
    page.driver.browser.execute_cdp("Input.dispatchTouchEvent", type: "touchEnd", touchPoints: [])
    assert_field "invoice-number-format-editor", with: "RE-[Monat]-[Fortlaufendenummer]"
    assert_selector ".invoice-number-token__description", count: 7
    assert_no_horizontal_overflow
    page.execute_script("arguments[0].scrollIntoView({behavior: 'instant'})", find(".invoice-number-tokens"))
    page.save_screenshot(Rails.root.join("tmp/screenshots/invoice-token-cards-mobile.png"))
  end

  test "Platzhalterbuttons fuegen an der Cursorposition ein und ersetzen Markierungen" do
    find("#invoice-number-preview").click
    within ".invoice-number-editor" do
      find("#invoice-number-format-editor").set("RE--[Fortlaufendenummer]")
      field = find("#invoice-number-format-editor")
      page.execute_script("arguments[0].focus(); arguments[0].setSelectionRange(3, 3)", field)
      find("button[data-token='[Jahr]']").click
      assert_equal "RE-[Jahr]-[Fortlaufendenummer]", field.value
      page.execute_script("arguments[0].focus(); arguments[0].setSelectionRange(0, 2)", field)
      find("button[data-token='[Kundenkürzel]']").click
      assert_equal "[Kundenkürzel]-[Jahr]-[Fortlaufendenummer]", field.value
      assert_equal "invoice-number-format-editor", page.evaluate_script("document.activeElement.id")
    end
  end

  test "Strg-Z macht Eingaben im Rechnungsnummernformat rueckgaengig" do
    find("#invoice-number-preview").click
    editor = find("#invoice-number-format-editor")
    initial_format = editor.value
    editor.send_keys("X")
    assert_equal "#{initial_format}X", editor.value
    undo_cancelled = page.evaluate_script(<<~JS)
      (() => {
        const event = new KeyboardEvent('keydown', { key: 'z', ctrlKey: true, bubbles: true, cancelable: true });
        document.querySelector('#invoice-number-format-editor').dispatchEvent(event);
        return event.defaultPrevented;
      })()
    JS
    assert_equal true, undo_cancelled
    assert_equal initial_format, editor.value
    page.execute_script("document.querySelector('#invoice-number-format-editor').dispatchEvent(new KeyboardEvent('keydown', { key: 'z', ctrlKey: true, shiftKey: true, bubbles: true, cancelable: true }))")
    assert_equal "#{initial_format}X", editor.value
  end

  test "Cursor bleibt nach dem Loeschen von Text hinter einem Platzhalter am Ende" do
    find("#invoice-number-preview").click
    editor = find("#invoice-number-format-editor")
    format = "RE-[Jahr]-[Fortlaufendenummer]"
    editor.set("#{format}Q")
    editor.set(format)
    editor.click
    editor.send_keys(:end)
    editor.send_keys("123")
    3.times do |index|
      editor.send_keys(:backspace)
      assert_equal format.length + 2 - index, editor.evaluate_script("this.selectionStart")
    end
    assert_equal format, editor.value
    editor.send_keys(:arrow_right)
    assert_equal format.length, editor.evaluate_script("this.selectionStart")
    editor.send_keys("Y")
    assert_equal "#{format}Y", editor.value
  end

  test "eigenes Nummernformat aktualisiert Datum und Kuerzel und ergaenzt automatische Zusaetze" do
    fill_invoice
    assert_no_selector "#invoice_buyer_abbreviation", visible: :visible
    find("#invoice-number-preview").click
    find('.invoice-number-template[data-format="[Kundenkürzel]-[Jahr]-[Monat]-[Tag]-[Tageszähler]"]').click
    assert_selector "#invoice-number-adjustment-title", visible: :visible
    link = find("#invoice-number-format-preview a", text: "Kundenkürzel")
    assert_match(/#invoice-number-abbreviation-editor\z/, link[:href])
    link.click
    assert_equal "invoice-number-abbreviation-editor", page.evaluate_script("document.activeElement.id")
    assert_selector "#invoice-number-editor[open]"
    fill_in "invoice-number-abbreviation-editor", with: "BEG"
    expected = "BEG-#{Date.current.strftime('%Y-%m-%d')}-01"
    assert_selector "#invoice-number-format-preview", text: expected
    find("[aria-label='Bearbeitung der Rechnungsnummer schließen']").click
    assert_field "invoice_buyer_abbreviation", with: "BEG"
    assert_field "invoice-number-preview", with: expected
    fill_in "invoice_issued_on_display", with: (Date.current + 1).strftime("%d.%m.%Y")
    assert_field "invoice-number-preview", with: "BEG-#{(Date.current + 1).strftime('%Y-%m-%d')}-01"
    fill_in "invoice_issued_on_display", with: Date.current.strftime("%d.%m.%Y")
    assert_field "invoice-number-preview", with: expected
    click_button "Festschreiben"
    assert_selector ".print-invoice h1", text: expected
    %w[02 03].each do |suffix|
      visit new_invoice_path
      fill_invoice
      fill_in "invoice_buyer_abbreviation", with: "BEG"
      assert_field "invoice-number-preview", with: "#{expected.delete_suffix("01")}#{suffix}"
      count = Invoice.count
      click_button "Festschreiben"
      assert_equal count + 1, Invoice.count
      assert_selector ".print-invoice h1", text: "#{expected.delete_suffix("01")}#{suffix}"
    end
  end

  test "ungueltiges Feld wird bei Vorschau ueber den Footer hinaus sichtbar gescrollt" do
    resize_browser(390, 700)
    page.execute_script("window.scrollTo(0, document.body.scrollHeight)")
    click_button "Vorschau"
    assert_equal "invoice_seller_name", page.evaluate_script("document.activeElement.id")
    assert page.evaluate_script(<<~JS)
      (() => {
        const field = document.querySelector('#invoice_seller_name').getBoundingClientRect();
        const footer = document.querySelector('.invoice-form__actions').getBoundingClientRect();
        return field.top >= 0 && field.bottom <= footer.top;
      })()
    JS
  end

  test "leere und ungueltige Felder verhindern Erstellen und Vorschau" do
    count = Invoice.count
    click_button "Festschreiben"
    assert_equal "invoice_seller_name", page.evaluate_script("document.activeElement.id")
    fill_invoice
    fill_in "invoice_buyer_email", with: "ungueltig"
    click_button "Vorschau"
    assert_equal "invoice_buyer_email", page.evaluate_script("document.activeElement.id")
    assert_equal 1, page.driver.browser.window_handles.size
    fill_in "invoice_buyer_email", with: "kunde@example.test"
    fill_in line_id("description"), with: ""
    click_button "Festschreiben"
    assert_equal line_id("description"), page.evaluate_script("document.activeElement.id")
    assert_equal count, Invoice.count
  end

  test "Mehr oeffnet den Hilfeartikel und behaelt das Rechnungsformular" do
    fill_in "invoice_seller_tax_identifier", with: "12/345/67890"
    assert_no_selector "[popovertarget=tax-id-details]"
    help_window = window_opened_by { within("#tax-id-help") { click_link "Mehr" } }
    within_window help_window do
      assert_current_path hilfe_path
      assert_equal "#steuernummer-oder-umsatzsteuer-id", page.evaluate_script("location.hash")
      assert_selector "h1", text: "Hilfe"
      assert_selector "article#steuernummer-oder-umsatzsteuer-id", text: "Was ist der Unterschied?"
      assert_text "Du musst sie beantragen"
    end
    help_window.close
    within "section[aria-labelledby='e-invoice-hint-title']" do
      assert_text "Musst du eine E-Rechnung ausstellen?"
      assert_text "Das gilt dauerhaft"
      assert_text "Die Pflicht, die ab 2027 und 2028 greift, betrifft nur Unternehmen, die Umsatzsteuer ausweisen."
      assert_text "Du kannst eine E-Rechnung freiwillig erstellen."
      assert_text "Eine normale PDF- oder Papierrechnung bleibt für dich erlaubt."
      assert_text "Empfangen musst du E-Rechnungen aber können, zum Beispiel per E-Mail."
      assert_selector ".invoice-hint__answer strong", text: "Nein."
      assert_link "§ 34a UStDV", href: "https://www.gesetze-im-internet.de/ustdv_1980/__34a.html"
      assert_no_selector ".invoice-hint__answer strong", text: /empfangen/
      assert_no_selector "summary"
    end
    invoice_help = window_opened_by { within("section[aria-labelledby='e-invoice-hint-title']") { click_link "Weiteres zur E-Rechnung in der Hilfe" } }
    within_window invoice_help do
      assert_current_path hilfe_path
      assert_equal "#e-rechnung", page.evaluate_script("location.hash")
      assert_selector "article#e-rechnung h3", text: "XRechnung oder ZUGFeRD?"
    end
    invoice_help.close
    assert_field "invoice_seller_tax_identifier", with: "12/345/67890"
  end

  test "Vorschau Popover schliesst per Escape und Aussenklick und bleibt mobil bedienbar" do
    fill_invoice
    windows = page.driver.browser.window_handles.size
    click_button "Vorschau"
    assert_selector "dialog.invoice-preview-dialog[open]"
    assert_equal windows, page.driver.browser.window_handles.size
    within_frame("invoice-preview-frame") do
      assert_selector ".invoice-pages:not(.invoice-pages--rendering) .pagedjs_page"
      assert_no_selector ".site-header"
      find("body").send_keys(:escape)
    end
    assert_no_selector "dialog.invoice-preview-dialog[open]"
    assert_equal "Vorschau", page.evaluate_script("document.activeElement.value")
    assert_field "invoice_buyer_name", with: "Testkunde GmbH"
    click_button "Vorschau"
    assert_selector "dialog.invoice-preview-dialog[open]"
    page.save_screenshot(Rails.root.join("tmp/screenshots/invoice-preview-popover.png"))
    page.driver.browser.action.move_to_location(2, 2).click.perform
    assert_no_selector "dialog.invoice-preview-dialog[open]"
    page.current_window.resize_to(390, 844)
    click_button "Vorschau"
    assert_selector "dialog.invoice-preview-dialog[open]"
    within_frame("invoice-preview-frame") { assert_selector ".invoice-pages:not(.invoice-pages--rendering) .pagedjs_page" }
    assert_no_horizontal_overflow
    page.save_screenshot(Rails.root.join("tmp/screenshots/invoice-preview-popover-mobile.png"))
    click_button "Vorschau schließen"
    assert_no_selector "dialog.invoice-preview-dialog[open]"
  ensure
    page.current_window.resize_to(1400, 1100)
  end

  test "Vorschau ist wiederholbar und speichert auch sofortige Aenderungen" do
    fill_invoice
    count = Invoice.count
    2.times do |index|
      fill_in "invoice_buyer_name", with: "Vorschaukunde #{index}"
      click_button "Vorschau"
      assert_selector "dialog.invoice-preview-dialog[open]"
      within_frame("invoice-preview-frame") do
        assert_match %r{\A/rechnungen/entwuerfe/\d+/vorschau\z}, page.evaluate_script("location.pathname")
        assert_text "Vorschaukunde #{index}"
        page.execute_script("location.reload()")
        assert_text "Vorschaukunde #{index}"
      end
      click_button "Vorschau schließen"
      assert_current_path %r{\A/rechnungen/entwuerfe/\d+/bearbeiten\z}
    end
    assert_equal count, Invoice.count
    assert_equal 1, InvoiceDraft.active.count
  end

  test "Entwurf behaelt Daten und deaktivierte Zahlungsfrist beim Fortsetzen" do
    fill_invoice
    fill_in "invoice_payment_due_on_display", with: ""
    click_link "Später"
    assert_current_path invoices_path
    assert_selector ".invoice-draft-card", count: 1
    row = find(".invoice-draft-card.invoice-list__item--draft")
    title = row.find("span", text: "Testkunde GmbH", exact_text: true)
    width = title.evaluate_script("this.getBoundingClientRect().width").to_i
    page.driver.browser.action.move_to(title.native, -width / 2 + 2, 0).click_and_hold.pause(duration: 0.2).move_by(width - 4, 0).pause(duration: 0.2).release.perform
    assert_current_path invoices_path
    assert page.evaluate_script("window.getSelection().toString().length > 0")
    page.execute_script("window.getSelection().removeAllRanges()")
    row.find("span", text: "Testkunde GmbH", exact_text: true).click
    assert_field "invoice_seller_name", with: "Teststudio Müller"
    assert_field "invoice_buyer_name", with: "Testkunde GmbH"
    assert_field line_id("description"), with: "Beratung"
    assert_field "invoice_payment_due_on_display", with: ""
    assert_nil InvoiceDraft.active.sole.data["payment_due_on"]
    dismiss_confirm { click_button "Verwerfen" }
    assert_field "invoice_buyer_name", with: "Testkunde GmbH"
    assert_equal 1, InvoiceDraft.active.count
    accept_confirm { click_button "Verwerfen" }
    assert_current_path invoices_path
    assert_no_selector ".invoice-draft-card"
    assert_equal 0, InvoiceDraft.active.count
  end

  test "mobile Entwurfsliste zeigt Kunden ohne leere Titelspalte" do
    fill_invoice
    click_link "Später"
    assert_current_path invoices_path
    assert_selector ".invoice-draft-card", count: 1
    draft = InvoiceDraft.active.sole
    draft.update!(data: draft.data.merge("title" => "", "buyer_name" => ""))
    [ 320, 390, 430 ].each do |width|
      resize_browser(width, 844)
      visit invoices_path
      row = find(".invoice-draft-card")
      assert_no_selector ".invoice-draft-card > .invoice-list__identity"
      assert_selector ".invoice-draft-card__customer", text: "Kunde noch nicht angegeben"
      assert row.evaluate_script(<<~JS)
        (() => {
          const customer = this.querySelector('.invoice-draft-card__customer').getBoundingClientRect();
          const badges = this.querySelector('.invoice-list__labels').getBoundingClientRect();
          return Math.abs(customer.left - badges.left) < 1 && Math.abs(customer.width - badges.width) < 1;
        })()
      JS
      assert_no_horizontal_overflow
      page.save_screenshot(Rails.root.join("tmp/screenshots/invoice-draft-empty-#{width}.png")) if width == 390
    end
    draft.update!(data: draft.data.merge("title" => "Website-Anpassungen", "buyer_name" => "Testkunde GmbH"))
    visit invoices_path
    assert_selector ".invoice-draft-card .invoice-list__identity", text: "Website-Anpassungen"
    assert_selector ".invoice-draft-card__customer", text: "Testkunde GmbH"
    find(".invoice-draft-card__customer").click
    assert_field "invoice_buyer_name", with: "Testkunde GmbH"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.current_window.resize_to(1400, 1100)
  end

  test "Entwurf laesst sich ueber das Muelltonnen Icon loeschen" do
    page.current_window.resize_to(390, 844)
    fill_invoice
    click_link "Später"
    within ".invoice-draft-card" do
      assert_selector ".invoice-draft-card__amount button[aria-label='Verwerfen'] svg"
      assert_no_selector ".invoice-list__labels button"
      assert find(".invoice-draft-card__amount").evaluate_script(<<~JS)
        (() => {
          const amount = this.querySelector('strong').getBoundingClientRect();
          const button = this.querySelector('button').getBoundingClientRect();
          return button.left > amount.right && Math.abs((button.top + button.bottom - amount.top - amount.bottom) / 2) < 1;
        })()
      JS
      assert_no_selector "button[aria-label='Verwerfen'] span"
      dismiss_confirm("Entwurf wirklich verwerfen? Die gespeicherten Angaben gehen dabei verloren.") { click_button "Verwerfen" }
      assert_equal 1, InvoiceDraft.active.count
      assert_selector ".invoice-draft-card__link"
      accept_confirm { click_button "Verwerfen" }
    end
    assert_current_path invoices_path
    assert_no_selector ".invoice-draft-card"
    assert_equal 0, InvoiceDraft.active.count
  end

  test "Heute ist beim Bis-Datum nur innerhalb des erlaubten Zeitraums waehlbar" do
    fill_in "invoice_service_on_display", with: Date.current.strftime("%d.%m.%Y")
    find("#invoice_service_until_on_display").click
    within "#service_until_on-calendar" do
      assert_button "Heute", disabled: true
    end
    find("#invoice_service_until_on_display").send_keys(:escape)
    fill_in "invoice_service_on_display", with: Date.yesterday.strftime("%d.%m.%Y")
    find("#invoice_service_until_on_display").click
    within "#service_until_on-calendar" do
      assert_button "Heute", disabled: false
      click_button "Heute"
    end
    assert_field "invoice_service_until_on_display", with: Date.current.strftime("%d.%m.%Y")
  end

  test "Bis Kalender beginnt passend zum Leistungsbeginn und behaelt ein gewaehltes Ende" do
    fill_in "invoice_service_on_display", with: "01.11.2026"
    ending = find("#invoice_service_until_on_display")
    ending.click
    within "#service_until_on-calendar" do
      assert_selector ".date-picker__header strong", text: "November 2026"
      assert_selector "button[data-date='2026-11-01']:disabled"
      assert_selector "button[data-date='2026-11-02']:enabled"
    end
    ending.send_keys(:escape)
    ending.send_keys([ :alt, :arrow_down ])
    assert_equal "2026-11-02", page.evaluate_script("document.activeElement.dataset.date")
    find("#service_until_on-calendar button[data-date='2026-11-30']").click
    assert_field "invoice_service_until_on_display", with: "30.11.2026"
    ending.click
    assert_selector "#service_until_on-calendar .date-picker__header strong", text: "November 2026"
    assert_selector "#service_until_on-calendar button[data-date='2026-11-30'][aria-pressed=true]"
  end

  test "Datumsvalidierung und Leistungszeitraum funktionieren mit dem deutschen Datumseingabefeld" do
    fill_invoice
    fill_in "invoice_issued_on_display", with: "08.10.2026"
    fill_in "invoice_payment_due_on_display", with: "07.10.2026"
    click_button "Festschreiben"
    assert_equal "invoice_payment_due_on_display", page.evaluate_script("document.activeElement.id")
    assert_includes page.evaluate_script("document.activeElement.validationMessage"), "Rechnungsdatum"
    fill_in "invoice_payment_due_on_display", with: "31.02.2026"
    click_button "Festschreiben"
    assert_includes page.evaluate_script("document.activeElement.validationMessage"), "gültiges Datum"
    fill_in "invoice_payment_due_on_display", with: ""
    assert_field "invoice_service_until_on_display"
    assert_equal false, find("#invoice_service_until_on_display").evaluate_script("this.required")
    fill_in "invoice_service_on_display", with: "01.10.2026"
    fill_in "invoice_service_until_on_display", with: "30.09.2026"
    click_button "Festschreiben"
    assert_equal "invoice_service_until_on_display", page.evaluate_script("document.activeElement.id")
    assert_includes page.evaluate_script("document.activeElement.validationMessage"), "nach dem Von-Datum"
    fill_in "invoice_service_until_on_display", with: "01.10.2026"
    click_button "Festschreiben"
    assert_equal "invoice_service_until_on_display", page.evaluate_script("document.activeElement.id")
    assert_includes page.evaluate_script("document.activeElement.validationMessage"), "Für einen einzelnen Tag lass es leer."
    fill_in "invoice_service_until_on_display", with: "05.10.2026"
    click_button "Festschreiben"
    assert_current_path %r{\A/rechnungen/\d+\z}
    invoice = Invoice.order(:id).last
    assert_equal Date.new(2026, 10, 5), invoice.service_until_on
    assert_nil invoice.payment_due_on
  end

  test "Positionen hinzufuegen loeschen und letzte Position leeren" do
    fill_invoice
    fill_in line_id("quantity"), with: "2"
    fill_in line_id("unit_price"), with: "10"
    assert_selector "[data-invoice-lines-target=total]", text: "20,00"
    click_button "Position hinzufügen"
    fill_in line_id("description", 1), with: "Buch"
    fill_in line_id("unit_price", 1), with: "5"
    assert_selector "[data-invoice-lines-target=total]", text: "25,00"
    all("button[aria-label='Position löschen']").last.click
    assert_selector ".invoice-line", count: 1
    assert_selector "[data-invoice-lines-target=total]", text: "20,00"
    click_button "Position leeren"
    assert_field line_id("description"), with: ""
    assert_selector "[data-invoice-lines-target=total]", text: "0,00"
    click_button "Festschreiben"
    assert_equal line_id("description"), page.evaluate_script("document.activeElement.id")
  end

  test "Summen runden pro Position und stimmen ohne Umsatzsteuer mit der fertigen Rechnung ueberein" do
    fill_invoice
    fill_in line_id("quantity"), with: "0.5"
    fill_in line_id("unit_price"), with: "0.01"
    click_button "Position hinzufügen"
    fill_in line_id("description", 1), with: "Zweite Leistung"
    fill_in line_id("quantity", 1), with: "0.5"
    fill_in line_id("unit_price", 1), with: "0.01"
    assert_selector "[data-invoice-lines-target=total]", text: "0,02"
    click_button "Position hinzufügen"
    fill_in line_id("description", 2), with: "Buch"
    fill_in line_id("unit_price", 2), with: "10"
    assert_selector "[data-invoice-lines-target=total]", text: "10,02"
    click_button "Festschreiben"
    assert_current_path %r{\A/rechnungen/\d+\z}
    assert_equal BigDecimal("10.02"), Invoice.order(:id).last.total
  end

  test "Speicherfehler verhindern das Verlassen und koennen erneut versucht werden" do
    fill_invoice
    page.execute_script <<~JS
      window.workingFetch = window.fetch;
      window.fetch = (url, options) => options?.method === 'PATCH'
        ? Promise.resolve(new Response('', { status: 503 })) : window.workingFetch(url, options);
    JS
    fill_in "invoice_buyer_name", with: "Noch nicht gespeichert"
    click_link "Später"
    assert_selector "[data-invoice-draft-target=status]", text: "Entwurf konnte nicht gespeichert werden"
    assert_selector "form.invoice-form"
    page.execute_script "window.fetch = window.workingFetch"
    click_link "Später"
    assert_current_path invoices_path
    assert_text "Noch nicht gespeichert"
  end

  test "ungueltige IBAN wird vor Vorschau und Erstellung angezeigt" do
    fill_invoice
    select "Überweisung", from: "Zahlungsart"
    fill_in "invoice_iban", with: "DE 12345678"
    assert_selector "[data-iban-field-target=status]", text: "Zu kurz"
    assert_equal false, find("#invoice_iban").evaluate_script("this.validity.valid")
    click_button "Vorschau"
    assert_equal 1, page.driver.browser.window_handles.size
    assert_equal "invoice_iban", page.evaluate_script("document.activeElement.id")
    select "Überweisung", from: "Zahlungsart"
    fill_in "invoice_iban", with: "DE89370400440532013001"
    click_button "Festschreiben"
    assert_selector "[data-iban-field-target=status]", text: "Prüfsumme"
    assert_selector "form.invoice-form"
    assert_field "invoice_buyer_name", with: "Testkunde GmbH"
    assert_field line_id("description"), with: "Beratung"
    select "Überweisung", from: "Zahlungsart"
    fill_in "invoice_iban", with: "DE89 3704 0044 0532 0130 00"
    click_button "Festschreiben"
    assert_current_path %r{\A/rechnungen/\d+\z}
    assert_equal "DE89370400440532013000", Invoice.order(:id).last.iban
  end

  test "Preis null oeffnet Vorschau ohne Abfrage und verlangt Bestaetigung beim Festschreiben" do
    fill_invoice
    fill_in line_id("unit_price"), with: "0"
    count = Invoice.count
    dismiss_confirm(/0 €/) { click_button "Festschreiben" }
    assert_selector "form.invoice-form"
    assert_equal count, Invoice.count
    click_button "Vorschau"
    assert_selector "dialog.invoice-preview-dialog[open]"
    within_frame("invoice-preview-frame") do
      assert_selector ".invoice-preview-warning", text: "Achtung: Preis von 0,00 € in Position 1."
      assert_no_selector ".print-invoice .invoice-preview-warning"
      assert_no_selector ".invoice-payment"
      assert_no_text "Bitte überweise"
    end
    click_button "Vorschau schließen"
    accept_confirm(/0 €/) { click_button "Festschreiben" }
    assert_current_path %r{\A/rechnungen/\d+\z}
    assert_equal count + 1, Invoice.count
    assert_equal 0, Invoice.order(:id).last.total
  end

  test "Impressum Daten werden erst nach Pruefung und Uebernahme eingefuegt" do
    page.execute_script <<~JS
      const fetchBeforeLookup = window.fetch;
      window.fetch = (url, options) => {
        if (!String(url).endsWith('/kundenimpressum-suchen')) return fetchBeforeLookup(url, options);
        window.lookupBody = JSON.parse(options.body);
        return Promise.resolve(new Response(JSON.stringify({ buyer_name: 'Impressum GmbH', buyer_street: 'Testweg 12', buyer_city: 'Hamburg', buyer_postal_code: '20095', buyer_country: 'DE', buyer_email: 'kontakt@example.test' }), { status: 200, headers: { 'Content-Type': 'application/json' } }));
      };
    JS
    fill_in "invoice_buyer_name", with: "Bisheriger Kunde"
    assert_no_selector "#customer-imprint-lookup"
    click_button "Kundendaten aus Impressum"
    assert_selector "#customer-imprint-lookup"
    fill_in "customer_imprint_domain", with: "https://example.test/impressum"
    click_button "Daten ermitteln"
    assert_selector "#customer-imprint-lookup .imprint-lookup__data", text: "Impressum GmbH"
    assert_selector "#customer-imprint-lookup .imprint-lookup__data", text: "Testweg 12"
    assert_field "invoice_buyer_name", with: "Bisheriger Kunde"
    assert_field "invoice_buyer_street", with: ""
    click_button "Abbrechen"
    assert_no_selector "#customer-imprint-lookup"
    assert_field "invoice_buyer_name", with: "Bisheriger Kunde"
    click_button "Kundendaten aus Impressum"
    fill_in "customer_imprint_domain", with: "https://example.test/anderes-impressum"
    assert_no_selector ".imprint-lookup__results"
    click_button "Daten ermitteln"
    assert_selector ".imprint-lookup__data", text: "kontakt@example.test"
    resize_browser(390, 844)
    assert_equal true, find("#customer-imprint-lookup").evaluate_script("this.scrollWidth <= this.clientWidth")
    page.save_screenshot(Rails.root.join("tmp/screenshots/imprint-results-mobile.png"))
    click_button "Daten übernehmen"
    assert_no_selector "#customer-imprint-lookup"
    assert_field "invoice_buyer_name", with: "Impressum GmbH"
    assert_field "invoice_buyer_street", with: "Testweg 12"
    assert_field "invoice_buyer_email", with: "kontakt@example.test"
    assert_no_text "Kundendaten eingefügt"
    assert_no_text "im Popup prüfen und anschließend übernehmen"
    assert_selector ".imprint-lookup__hint", text: "Ermittle Kundendaten aus dem Impressum der Kundenwebseite."
    assert_selector "[data-invoice-draft-target=status]", text: "Entwurf gespeichert"
    assert_equal "Impressum GmbH", InvoiceDraft.active.sole.data["buyer_name"]
    assert_equal "https://example.test/anderes-impressum", page.evaluate_script("window.lookupBody.domain")
  end

  test "Impressum Fehler bleibt im Popover sichtbar und veraendert keine Kundenfelder" do
    page.execute_script <<~JS
      const fetchBeforeLookup = window.fetch;
      window.fetch = (url, options) => String(url).endsWith('/kundenimpressum-suchen')
        ? Promise.resolve(new Response(JSON.stringify({ error: 'Keine Angaben gefunden' }), { status: 422 }))
        : fetchBeforeLookup(url, options);
    JS
    fill_in "invoice_buyer_name", with: "Manuell eingetragen"
    click_button "Kundendaten aus Impressum"
    fill_in "customer_imprint_domain", with: "example.test"
    find("#customer_imprint_domain").send_keys(:enter)
    assert_selector "#customer-imprint-lookup [data-error=true]", text: "Keine Angaben gefunden"
    assert_button "Daten ermitteln", disabled: false
    page.driver.browser.action.send_keys(:escape).perform
    assert_field "invoice_buyer_name", with: "Manuell eingetragen"
  end

  test "Impressum Popover passt auf einen mobilen Bildschirm und laesst sich schliessen" do
    resize_browser(390, 844)
    click_button "Kundendaten aus Impressum"
    assert_selector "#customer-imprint-lookup"
    assert_equal 390, page.evaluate_script("innerWidth")
    assert_equal true, find("#customer-imprint-lookup").evaluate_script("this.scrollWidth <= this.clientWidth")
    page.save_screenshot(Rails.root.join("tmp/screenshots/imprint-popover-mobile.png"))
    find(".form-popover__close").click
    assert_no_selector "#customer-imprint-lookup"
  end

  test "Rechnungsnummer laesst sich im Popup bearbeiten und folgt dem Tag des Rechnungsdatums" do
    assert_selector "#invoice-number-preview[readonly]"
    assert_selector "#invoice-number-editor:not([open])", visible: :all
    number_top, date_top, field_width, grid_width = page.evaluate_script(<<~JS)
      (() => {
        const number = document.querySelector('#invoice-number-preview');
        const date = document.querySelector('#invoice_issued_on_display');
        const field = number.closest('.field');
        return [number, date, field, field.parentElement].map(element => {
          const rect = element.getBoundingClientRect();
          return element === field || element === field.parentElement ? rect.width : rect.top;
        });
      })()
    JS
    assert_operator date_top, :>, number_top
    assert_in_delta grid_width, field_width, 1
    find("#invoice-number-preview").click
    assert_selector "#invoice-number-editor[open]"
    assert_no_selector ".invoice-number-result"
    find('.invoice-number-template[data-format="[Jahr]-[Monat]-[Tag]-[Fortlaufendenummer]"]').click
    find("[aria-label='Bearbeitung der Rechnungsnummer schließen']").click
    assert_field "invoice-number-preview", with: "#{Date.current.iso8601}-0001"
    fill_in "invoice_issued_on_display", with: "01.01.2028"
    assert_field "invoice-number-preview", with: "2028-01-01-0001"
    assert_no_selector "#due_date_enabled"
  end

  test "geleertes Leistungsende erlaubt ein einzelnes Leistungsdatum" do
    fill_invoice
    fill_in "invoice_service_until_on_display", with: "31.02.2026"
    fill_in "invoice_service_until_on_display", with: ""
    click_button "Festschreiben"
    assert_current_path %r{\A/rechnungen/\d+\z}
    assert_nil Invoice.order(:id).last.service_until_on
  end

  test "Kundenwechsel aktualisiert Zahlungsfrist Stundensatz und BIC Anzeige" do
    fill_invoice
    find("#invoice_buyer_hourly_rate").click
    fill_in "Individueller Stundensatz", with: "50"
    select "Überweisung", from: "Zahlungsart"
    fill_in "invoice_iban", with: "DE89370400440532013000"
    select "Stunde", from: line_id("unit_code")
    assert_no_selector ".invoice-line__price button[aria-label='Rechner öffnen']"
    assert_no_selector ".invoice-line__quantity button[aria-label='Rechner öffnen']"
    fill_in "invoice_payment_due_on_display", with: ""
    select "Vereinigte Staaten", from: "invoice_buyer_country"
    assert_field "invoice_bic"
    fill_in "invoice_bic", with: "COBADEFFXXX"
    click_button "Festschreiben"
    assert_current_path %r{\A/rechnungen/\d+\z}
    customer = Customer.order(:id).last
    customer.workspace.customers.create!(name: "Anderer Kunde", street: "Weg 3", postal_code: "10115",
      city: "Berlin", country: "DE", hourly_rate: 80, payment_due_days: 7)
    visit new_invoice_path
    fill_in "invoice_buyer_name", with: "Testkunde"
    find("#customer-name-suggestions li", text: "Testkunde GmbH, Berlin").click
    assert_field "invoice_payment_due_on_display", with: ""
    assert_field "invoice_payment_due_on_display", with: ""
    assert_field "invoice_bic"
    select "Stunde", from: line_id("unit_code")
    assert_field line_id("unit_price"), with: "50,00"
    fill_in "invoice_buyer_name", with: "anderer"
    find("#invoice_buyer_name").send_keys(:arrow_down, :enter)
    assert_field "invoice_buyer_name", with: "Anderer Kunde"
    assert_field "invoice_buyer_street", with: "Weg 3"
    assert_no_selector "#customer-name-suggestions"
    assert_field "invoice_payment_due_on_display", with: (Date.current + 7).strftime("%d.%m.%Y")
    assert_field line_id("unit_price"), with: "80,00"
    assert_no_selector "#invoice_bic"
  end

  test "zwei Formulare speichern und loeschen unabhaengige Entwuerfe" do
    fill_invoice
    assert_selector "[data-invoice-draft-target=status]", text: "Entwurf gespeichert"
    first_draft = InvoiceDraft.active.sole
    first_window = current_window
    other_window = open_new_window
    within_window other_window do
      visit new_invoice_path
      fill_in "invoice_buyer_name", with: "Zweiter Entwurf"
      assert_selector "[data-invoice-draft-target=status]", text: "Entwurf gespeichert"
      assert_current_path %r{\A/rechnungen/entwuerfe/\d+/bearbeiten\z}
      assert_equal 2, InvoiceDraft.active.count
      accept_confirm { click_button "Verwerfen" }
      assert_current_path invoices_path
      assert_text "Testkunde GmbH"
      assert_no_text "Zweiter Entwurf"
    end
    other_window.close
    within_window first_window do
      page.refresh
      assert_current_path edit_draft_invoices_path(draft_id: first_draft.id)
      assert_field "invoice_buyer_name", with: "Testkunde GmbH"
      assert_field line_id("description"), with: "Beratung"
    end
  end

  test "Direkte Stundenberechnung und formatierte Beschreibung bleiben im Entwurf erhalten" do
    resize_browser(390, 1100)
    fill_invoice
    select "Stunde", from: line_id("unit_code")
    fill_in line_id("quantity"), with: "20 min + 40 min + 0,5 Std"
    find_field(line_id("quantity")).send_keys(:enter)
    assert_field line_id("quantity"), with: "1.5"
    assert_selector ".rich-text__editor", visible: true
    editor = find(".rich-text__editor")
    editor.set("Projektarbeit")
    assert_selector ".rich-text__editor", text: "Projektarbeit"
    tops = page.evaluate_script("['unit_code','quantity','unit_price'].map(field => document.querySelector('#invoice_invoice_lines_attributes_0_' + field).getBoundingClientRect().top)")
    tops.each_cons(2) { |before, after| assert_operator after, :>, before }
    assert_no_horizontal_overflow
    assert_no_button "Rechner öffnen"
    assert_text "Kommazahlen und Rechenwege sind möglich"
    assert_selector "[data-invoice-lines-target=total]", text: "75,00"
    click_link "Später"
    find(".invoice-draft-card__link").click
    assert_field line_id("quantity"), with: "1.5"
    assert_selector ".rich-text__editor", text: "Projektarbeit"
    assert_selector "[data-invoice-lines-target=total]", text: "75,00"
  end

  test "Waehrung aktualisiert Summen und aktiviert nur bei Fremdwaehrung die Umrechnung" do
    resize_browser(390, 844)
    fill_invoice
    assert_selector "#invoice_currency option[selected]", text: "Euro (EUR)", visible: :all
    assert_no_selector ".currency-conversion"
    page.execute_script <<~JS
      const currencyFetch = window.fetch;
      window.fetch = (url, options) => String(url).includes('/rechnungen/wechselkurs')
        ? Promise.resolve(new Response(JSON.stringify({rate: '0.92', quote: '1.08695652', date: '2026-10-09', source: 'EZB-Referenzkurs'}), {status: 200}))
        : currencyFetch(url, options);
    JS
    select "US-Dollar (USD)", from: "Währung"
    assert_selector ".currency-conversion"
    assert_selector "[data-summary=total]", text: "USD"
    assert_selector "[data-invoice-lines-target=total]", text: "USD"
    assert_field "invoice_exchange_rate", disabled: false
    assert_field "invoice_exchange_rate", with: "1.08695652"
    assert_field "invoice_exchange_rate_source", with: "EZB-Referenzkurs"
    assert_field "invoice_exchange_rate_on_display", with: "09.10.2026", disabled: false
    fill_in "invoice_exchange_rate", with: "0.92"
    fill_in "invoice_exchange_rate_on_display", with: "11.10.2026"
    fill_in "invoice_exchange_rate_source", with: "Bankabrechnung"
    assert_no_horizontal_overflow
    select "Euro (EUR)", from: "Währung"
    assert_no_selector ".currency-conversion"
    assert_field "invoice_exchange_rate", disabled: true, visible: :all
    assert_field "invoice_exchange_rate_on_display", with: "", disabled: true, visible: :all
    assert_selector "[data-invoice-lines-target=total]", text: "€"
  end

  test "Datumsfeld bleibt neben dem Kalender sichtbar und direkt editierbar" do
    resize_browser(390, 844)
    field = find("#invoice_service_on_display")
    field.scroll_to(:center)
    scroll_before = page.evaluate_script("window.scrollY")
    field.click
    Timeout.timeout(3) do
      sleep 0.05 until page.evaluate_script("window.scrollY") > scroll_before
      sleep 0.05 until page.evaluate_script("(() => { const c = document.querySelector('#service_on-calendar').getBoundingClientRect(); const f = document.querySelector('.invoice-form__actions').getBoundingClientRect(); return c.bottom <= Math.min(window.innerHeight, f.top); })()")
    end
    assert_operator page.evaluate_script("window.scrollY"), :>, scroll_before
    assert_selector "#service_on-calendar", visible: true
    assert_equal "invoice_service_on_display", page.evaluate_script("document.activeElement.id")
    assert page.evaluate_script(<<~JS)
      (() => {
        const field = document.querySelector('#invoice_service_on_display').getBoundingClientRect();
        const calendar = document.querySelector('#service_on-calendar').getBoundingClientRect();
        const footer = document.querySelector('.invoice-form__actions').getBoundingClientRect();
        return field.top >= 0 && calendar.top >= field.bottom && calendar.bottom <= Math.min(window.innerHeight, footer.top);
      })()
    JS
    fill_in "invoice_service_on_display", with: "12.10.2026"
    assert_field "invoice_service_on_display", with: "12.10.2026"
    assert_equal "2026-10-12", find("#invoice_service_on", visible: :all).value
    field.click
    assert_equal "invoice_service_on_display", page.evaluate_script("document.activeElement.id")
  end

  test "offener Kalender verdeckt beim manuellen Scrollen keine Footer Buttons" do
    resize_browser(390, 844)
    field = find("#invoice_service_on_display")
    field.scroll_to(:center)
    field.click
    assert_selector "#service_on-calendar", visible: true
    sleep 0.5
    page.execute_script("window.scrollBy({ top: -150, behavior: 'instant' })")
    assert page.evaluate_script(<<~JS)
      (() => {
        const calendar = document.querySelector('#service_on-calendar').getBoundingClientRect();
        const footer = document.querySelector('.invoice-form__actions').getBoundingClientRect();
        const left = Math.max(calendar.left, footer.left);
        const right = Math.min(calendar.right, footer.right);
        const top = Math.max(calendar.top, footer.top);
        const bottom = Math.min(calendar.bottom, footer.bottom);
        if (left >= right || top >= bottom) return false;
        const hit = document.elementFromPoint((left + right) / 2, (top + bottom) / 2);
        return Boolean(hit?.closest('.invoice-form__actions'));
      })()
    JS
  end

  test "dunkles mobiles Formular und Kalender bleiben bedienbar" do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: "dark" } ])
    resize_browser(390, 844)
    assert_equal "dark", page.evaluate_script("getComputedStyle(document.documentElement).colorScheme")
    fill_invoice
    assert_selector "label[for=invoice_issued_on_display] .field-label__icon"
    within find("#invoice_issued_on_display").find(:xpath, "..") do
      find("#invoice_issued_on_display").click
      assert_selector "[role=dialog]"
      assert_no_selector ".date-picker__icon", visible: :all
      assert_no_selector "button[aria-label='Kalender öffnen']", visible: :all
      click_button "Heute"
    end
    assert_no_horizontal_overflow
    assert_field "invoice_issued_on_display", with: Date.current.strftime("%d.%m.%Y")
    page.save_screenshot(Rails.root.join("tmp/screenshots/invoice-form-mobile-dark.png"))
  ensure
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  [ 1400, 390 ].each do |width|
    test "Rechnung erstellen und Kundendaten wiederverwenden bei #{width} Pixeln" do
      resize_browser(width, 1100)
      fill_invoice
      buyer_name_top, buyer_contact_name_top = page.evaluate_script(
        "['invoice_buyer_name', 'invoice_buyer_contact_name'].map(id => document.getElementById(id).getBoundingClientRect().top)"
      )
      if width == 1400
        assert_in_delta buyer_name_top, buyer_contact_name_top, 1
      else
        assert_operator buyer_contact_name_top, :>, buyer_name_top
      end
      assert_no_horizontal_overflow
      %w[seller buyer].each do |prefix|
        top = page.evaluate_script("['postal_code','city','country'].map(field => document.querySelector('#invoice_#{prefix}_' + field).getBoundingClientRect().top)")
        assert_in_delta top[0], top[1], 1
        if width == 1400
          assert_in_delta top[0], top[2], 1
        else
          assert_operator top[2], :>, top[0]
        end
      end
      assert_no_selector "details.invoice-line"
      click_button "Position hinzufügen"
      assert_field line_id("description")
      assert_field line_id("description", 1)
      all("button[aria-label='Position löschen']").last.click
      page.execute_script("arguments[0].scrollIntoView({block: 'start', behavior: 'instant'})", find("#invoice-step-lines"))
      page.save_screenshot(Rails.root.join("tmp/screenshots/invoice-lines-#{width}.png"))
      click_button "Festschreiben"
      assert_current_path %r{\A/rechnungen/\d+\z}
      assert_text "Testkunde GmbH"
      assert_equal 0, InvoiceDraft.active.count
      visit new_invoice_path
      assert_field "invoice_seller_name", with: "Teststudio Müller", visible: :all
      assert_selector ".invoice-seller-summary", text: "Teststudio Müller"
      fill_in "invoice_buyer_name", with: "Testkunde"
      find("#customer-name-suggestions li", text: "Testkunde GmbH, Berlin").click
      assert_field "invoice_buyer_name", with: "Testkunde GmbH"
      assert_field "invoice_buyer_email", with: "kunde@example.test"
      assert_no_horizontal_overflow
    end
  end

  test "Stueck zeigt Pakete als Mengen Icon und andere Einheiten behalten ihre Symbole" do
    select "Stück", from: line_id("unit_code")
    assert_selector "[data-line-quantity-target=packagesIcon] svg"
    assert_no_selector "[data-line-quantity-target=quantityIcon]"
    assert_no_selector "[data-line-quantity-target=hourIcon]"
    select "Stunde", from: line_id("unit_code")
    assert_selector "[data-line-quantity-target=hourIcon] svg"
    assert_no_selector "[data-line-quantity-target=packagesIcon]"
    select "Tag", from: line_id("unit_code")
    assert_selector "[data-line-quantity-target=quantityLabel]", text: "Tage"
    assert_selector "[data-line-quantity-target=calendarIcon] svg"
    assert_no_selector "[data-line-quantity-target=quantityIcon]"
    select "Monat", from: line_id("unit_code")
    assert_selector "[data-line-quantity-target=quantityLabel]", text: "Monate"
    assert_selector "[data-line-quantity-target=calendarIcon] svg"
    assert_no_selector "[data-line-quantity-target=packagesIcon]"
  end

  test "Einheiten aendern Beschriftungen und Pauschalen bleiben beim Fortsetzen erhalten" do
    fill_invoice
    select "Stunde", from: line_id("unit_code")
    assert_selector "label", text: "Stunden"
    assert_selector "label", text: "Preis pro Stunde"
    fill_in line_id("quantity"), with: "4"
    select "Pauschal", from: line_id("unit_code")
    assert_no_field line_id("quantity")
    assert_selector "label", text: "Pauschalpreis"
    assert_selector "[data-invoice-lines-target=total]", text: "50,00"
    click_link "Später"
    find(".invoice-draft-card__link").click
    assert_select line_id("unit_code"), selected: "Pauschal"
    assert_no_field line_id("quantity")
    select "Stück", from: line_id("unit_code")
    assert_field line_id("quantity"), with: "1"
    assert_selector "label", text: "Preis pro Stück"
    select "Pauschal", from: line_id("unit_code")
    click_button "Festschreiben"
    assert_current_path %r{\A/rechnungen/\d+\z}
    assert_equal 1, Invoice.order(:id).last.invoice_lines.sole.quantity
  end

  test "lange Positionsbeschreibungen umbrechen ohne ueberlappende Betraege" do
    page.current_window.resize_to(1400, 1100)
    fill_invoice
    # Entspricht dem Fehler in Entwurf 34: drei Positionen und eine lange letzte Beschreibung.
    details = "<p>Datenschutzlink im externen Browser öffnen</p>" +
      "<p>Datenschutzerklärung von PDF in eine HTML-Seite ändern, damit sie auch unter Android geöffnet werden kann.</p>" +
      "<p>Link im externen Browser öffnen und nicht im InAppBrowser, da ansonsten Navigations-Buttons hinzugefügt werden müssten, die für das Formular keine Funktion hätten, da die Navigation dort per JS läuft.</p>" * 8 +
      "<p>Letzter Absatz der Beschreibung</p>"
    2.times do |index|
      click_button "Position hinzufügen"
      fill_in line_id("description", index + 1), with: "Projekt #{index + 2}"
      fill_in line_id("unit_price", index + 1), with: "50"
    end
    page.execute_script("arguments[0].value = arguments[1]; arguments[0].dispatchEvent(new Event('input', {bubbles:true}))", find("##{line_id('details', 2)}", visible: :all), details)
    click_button "Vorschau"
    assert_selector "dialog.invoice-preview-dialog[open]"
    within_frame("invoice-preview-frame") do
      assert_selector ".invoice-pages:not(.invoice-pages--rendering) .pagedjs_page", minimum: 2
      within ".invoice-pages" do
        assert_text "Letzter Absatz der Beschreibung"
        assert_text "1. Beratung"
        assert_text "2. Projekt 2"
        assert_text "3. Projekt 3"
        assert_text "Gesamtbetrag"
      end
      all(".invoice-pages .pagedjs_page").each do |invoice_page|
        within invoice_page do
          next unless has_selector?(".invoice-table", wait: 0)

          assert_selector ".invoice-table thead", count: 1
          assert_selector ".invoice-table thead th", text: "Positionen"
          assert_selector ".invoice-table thead th", text: "Menge"
          assert_selector ".invoice-table thead th", text: "Einzelpreis"
          assert_selector ".invoice-table thead th", text: "Betrag"
        end
      end
      assert page.evaluate_script(<<~JS), "Die Tabellen mit wiederholtem Header müssen innerhalb der Seite bleiben"
        Array.from(document.querySelectorAll('.invoice-pages .pagedjs_page')).every(page => {
          const bottom = page.querySelector('.pagedjs_page_content').getBoundingClientRect().bottom;
          return Array.from(page.querySelectorAll('.invoice-table')).every(table => table.getBoundingClientRect().bottom <= bottom + 1);
        })
      JS
      rows = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll('.invoice-pages .invoice-position-row')).map(row =>
          Array.from(row.cells).map(cell => { const r = cell.getBoundingClientRect(); return {left:r.left, right:r.right, width:r.width} }))
      JS
      assert_equal 3, rows.length
      rows.each do |cells|
        assert_in_delta rows.first.first["width"], cells.first["width"], 1
        cells.each_cons(2) { |left, right| assert_operator left["right"], :<=, right["left"] + 1 }
        cells.each { |cell| assert_operator cell["width"], :>, 50 }
      end
      page.save_screenshot(Rails.root.join("tmp/screenshots/invoice-long-description-small-business.png"))
    end
    click_button "Vorschau schließen"
  end

  test "Gesamtsumme auf einer Folgeseite zeigt keinen verwaisten Positionskopf" do
    fill_invoice
    click_button "Vorschau"
    assert_selector "dialog.invoice-preview-dialog[open]"
    within_frame("invoice-preview-frame") do
      assert_selector ".invoice-pages:not(.invoice-pages--rendering) .pagedjs_page"
      # Stellt den Grenzfall nach, in dem alle Positionen passen, die Summe aber umbricht.
      assert page.evaluate_async_script(<<~JS)
        const done = arguments[arguments.length - 1];
        const element = document.querySelector('[data-controller="invoice-pagination"]');
        const controller = window.Stimulus.getControllerForElementAndIdentifier(element, 'invoice-pagination');
        const row = controller.pagesTarget.querySelector('.invoice-position-row');
        const content = row.closest('.pagedjs_page_content');
        // Die eingebettete Vorschau ist skaliert; Zeilenhöhen brauchen unskalierte CSS-Pixel.
        const zoom = parseFloat(getComputedStyle(controller.pagesTarget).zoom) || 1;
        const remainingHeight = (content.getBoundingClientRect().bottom - row.getBoundingClientRect().top) / zoom;
        controller.teardown();
        controller.sourceTarget.querySelector('.invoice-position-row').style.height = `${remainingHeight - 4}px`;
        controller.connect();
        controller.ready.then(done);
      JS
      assert_selector ".invoice-pages .pagedjs_page", minimum: 2
      totals = all(".invoice-pages .invoice-table").find { |table| table.has_selector?("tfoot", wait: 0) }
      within totals do
        assert_text "Gesamtbetrag"
        assert_no_selector ".invoice-position-row"
        assert_no_selector ".invoice-table thead"
      end
      assert_selector ".invoice-pages .invoice-table thead", count: 1
    end
    click_button "Vorschau schließen"
  end

  private

  def resize_browser(width, height)
    page.driver.browser.manage.window.resize_to(width, height)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: width < 760)
  end

  def fill_invoice
    find(".invoice-seller-details > summary").click unless page.has_selector?("#invoice_seller_name", wait: 0)
    {
      seller_name: "Teststudio Müller", seller_email: "studio@example.test",
      seller_street: "Teststraße 1", seller_postal_code: "10115", seller_city: "Berlin",
      seller_tax_identifier: "12/345/67890", buyer_name: "Testkunde GmbH",
      buyer_email: "kunde@example.test", buyer_street: "Kundenweg 2",
      buyer_postal_code: "10115", buyer_city: "Berlin"
    }.each { |name, value| fill_in "invoice_#{name}", with: value }
    fill_in line_id("description"), with: "Beratung"
    fill_in line_id("unit_price"), with: "50"
  end

  def line_id(attribute, index = 0)
    "invoice_invoice_lines_attributes_#{index}_#{attribute}"
  end

  def assert_no_horizontal_overflow
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth"), "Das Formular ist breiter als der Bildschirm"
  end
end
