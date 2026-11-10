require "application_system_test_case"

class InvoicePaymentsSystemTest < ApplicationSystemTestCase
  setup do
    visit new_bookkeeping_entry_path(kind: "income")
    click_button "Buchungsart ändern" if page.has_button?("Buchungsart ändern", wait: 0)
    choose "bookkeeping_entry_kind_deposit"
    fill_in "Eingelegter Betrag in Euro", with: "1"
    fill_in "Beschreibung", with: "Start"
    click_button "Speichern"
    assert_selector "h2", text: "Deine Übersicht"
    workspace = BookkeepingEntry.order(:id).last.workspace
    @invoice = workspace.invoices.new(invoices(:one).attributes.except("id", "workspace_id", "invoice_number", "created_at", "updated_at", "customer_id").merge(issued_on: Date.current, service_on: Date.current, payment_due_on: Date.current + 14, buyer_name: "Zahlungskunde"))
    @invoice.invoice_lines.build(description: "Beratung", quantity: 1, unit_price: 100, unit_code: "C62")
    @invoice.save!
  end

  test "Kalendertag im Zahlungsdialog wird in das Zahlungsdatum uebernommen" do
    visit invoice_path(@invoice)
    click_link "Als bezahlt markieren"
    find_field("Datum des Zahlungseingangs").click
    chosen = Date.current - 1
    day = find(".payment-dialog button[data-date='#{chosen.iso8601}']")
    page.driver.browser.action.move_to(day.native).click_and_hold.perform
    assert_field "Datum des Zahlungseingangs", focused: true
    page.driver.browser.action.release.perform
    assert_field "Datum des Zahlungseingangs", with: chosen.strftime("%d.%m.%Y")
    assert_selector "#bookkeeping_entry_paid_on[value='#{chosen.iso8601}']", visible: :all
  end

  test "mobile Rechnungsliste zeigt Nummer und Kunde untereinander und Datum neben Betrag" do
    invoice = @invoice.workspace.invoices.new(@invoice.attributes.except("id", "invoice_number", "created_at", "updated_at", "customer_id").merge(
      invoice_number_format: "ABE-2026-10-19-02", buyer_name: "AngelTeiche Beverstedt", title: "IT-Support, Webseite"))
    invoice.invoice_lines.build(description: "Beratung", quantity: 1, unit_price: 120, unit_code: "C62")
    invoice.save!
    @invoice = invoice
    [ 320, 390, 430 ].each do |width|
      page.driver.browser.manage.window.resize_to(width, 844)
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: 844, deviceScaleFactor: 1, mobile: true)
      visit invoices_path
      row = find("#invoice_#{@invoice.id}")
      assert_text "IT-Support, Webseite"
      assert row.evaluate_script(<<~JS)
        (() => {
          const identity = this.querySelector('.invoice-list__identity').getBoundingClientRect();
          const customer = this.querySelector('.invoice-list__customer').getBoundingClientRect();
          const date = this.querySelector('.invoice-list__date').getBoundingClientRect();
          const amount = this.querySelector('.invoice-list__amount').getBoundingClientRect();
          return customer.top >= identity.bottom && date.top >= customer.bottom &&
            Math.abs(customer.left - identity.left) < 1 && Math.abs(customer.width - identity.width) < 1 &&
            amount.left > date.right && Math.abs((date.top + date.bottom - amount.top - amount.bottom) / 2) < 1;
        })()
      JS
      assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
      row.evaluate_script("this.scrollIntoView({block: 'center'})")
      page.save_screenshot(Rails.root.join("tmp/screenshots/invoice-list-mobile-#{width}.png"))
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.current_window.resize_to(1400, 1100)
  end

  test "Rechnungseintraege oeffnen sich beim Klick und lassen Text markieren" do
    visit invoices_path
    row = find("#invoice_#{@invoice.id}")
    number = row.find(".invoice-list__number")
    width = number.evaluate_script("this.getBoundingClientRect().width").to_i
    page.driver.browser.action.move_to(number.native, -width / 2 + 2, 0).click_and_hold.pause(duration: 0.2).move_by(width - 4, 0).pause(duration: 0.2).release.perform
    assert_current_path invoices_path
    assert page.evaluate_script("window.getSelection().toString().length > 0")
    page.execute_script("window.getSelection().removeAllRanges()")
    row.find("span", text: "Zahlungskunde", exact_text: true).click
    assert_current_path invoice_path(@invoice)

    page.current_window.resize_to(390, 844)
    visit invoices_path
    find("#invoice_#{@invoice.id} span", text: "Zahlungskunde", exact_text: true).click
    assert_current_path invoice_path(@invoice)
  ensure
    page.current_window.resize_to(1400, 1100)
  end

  test "cash payment explains the business cash balance and saves a partial private withdrawal on mobile" do
    page.current_window.resize_to(390, 844)
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    visit invoice_path(@invoice)
    click_link "Als bezahlt markieren"
    select "Bargeld / Betriebskasse", from: "Zahlungsart"
    assert_text "Zur Betriebskasse gehört Bargeld, das du für betriebliche Zahlungen bereithältst."
    assert_text "Wie möchtest du das Bargeld erfassen?"
    assert_selector ".payment-dialog button[type=submit] > svg.button-icon[aria-hidden=true]"
    assert_no_selector "[name='bookkeeping_entry[cash_usage]']:checked"
    choose "Bleibt in der Betriebskasse"
    assert_selector "[data-cash-payment-target=panel] .booking-type-option", count: 3
    assert_no_field "Privat übernommener Betrag in Euro"
    choose "Teilweise privat übernommen"
    assert_selector "[data-cash-payment-target=panel] .booking-type-option", count: 3
    fill_in "Privat übernommener Betrag in Euro", with: "33,34"
    page.save_screenshot(Rails.root.join("tmp/screenshots/cash-payment-mobile.png"))
    click_button "Rechnung als bezahlt markieren"
    assert_current_path invoices_path
    assert_selector "#invoice_#{@invoice.id}", text: "Bezahlt"
    assert_no_selector ".payment-dialog[open]"
    payment = @invoice.reload.payment_entry
    assert_equal "cash", payment.payment_account
    assert_equal "split", payment.cash_usage
    assert_equal BigDecimal("33.34"), payment.cash_private_amount
    assert_equal 100, payment.amount
    visit edit_bookkeeping_entry_path(payment)
    assert_select "Zahlungsart", selected: "Bargeld / Betriebskasse"
    assert_field "Privat übernommener Betrag in Euro", with: "33,34"
    assert_button "Rechnung als bezahlt markieren"
    assert_selector "[data-euer-entry-target=submit] > svg.button-icon[aria-hidden=true]"
    assert_text "Teilweise privat übernommen"
    assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")
    choose "Vollständig privat übernommen"
    assert_selector "[data-cash-payment-target=panel] .booking-type-option", count: 3
    assert_no_field "Privat übernommener Betrag in Euro"
    find_button("Rechnung als bezahlt markieren").evaluate_script("this.scrollIntoView({ block: 'center', behavior: 'instant' })")
    click_button "Rechnung als bezahlt markieren"
    assert_text "Vorgang aktualisiert."
    assert_equal 100, payment.reload.cash_private_amount
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    page.current_window.resize_to(1400, 1100)
  end

  test "payment calendar stays visible above the dialog on desktop and mobile" do
    [ 1000, 390 ].each do |width|
      page.current_window.resize_to(width, 844)
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: 844, deviceScaleFactor: 1, mobile: width < 500)
      visit invoice_path(@invoice)
      click_link "Als bezahlt markieren"
      dialog = find(".payment-dialog[open]")
      assert_select "Zahlungsart", selected: "Geschäftskonto"
      height = dialog.evaluate_script("this.scrollHeight")
      find("#bookkeeping_entry_paid_on_display").click
      calendar = find("#paid_on-calendar")
      assert calendar.evaluate_script(<<~JS)
        (() => {
          const rect = this.getBoundingClientRect();
          const button = this.querySelector('[data-date]:not(:disabled)');
          const day = button.getBoundingClientRect();
          return this.matches(':popover-open') && rect.top >= 0 && rect.bottom <= innerHeight &&
            rect.left >= 0 && rect.right <= innerWidth &&
            document.elementFromPoint(day.left + day.width / 2, day.top + day.height / 2) === button;
        })()
      JS
      assert_equal height, dialog.evaluate_script("this.scrollHeight")
      page.save_screenshot(Rails.root.join("tmp/screenshots/payment-calendar-#{width}.png"))
      calendar.find("button[data-date]:not(:disabled)", match: :first).click
      assert_no_selector "#paid_on-calendar"
      page.save_screenshot(Rails.root.join("tmp/screenshots/payment-dialog-#{width}.png"))
      click_button "Abbrechen"
    end
    assert_nil @invoice.reload.payment_entry
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.current_window.resize_to(1400, 1100)
  end

  test "marking an invoice paid creates a dated EÜR income and opens that payment on repetition" do
    visit invoices_path
    within "[data-invoice-id='#{@invoice.id}']" do
      assert_text "Zahlung ausstehend"
      click_link "Als bezahlt markieren"
    end
    assert_current_path invoices_path
    assert_selector "dialog[open] h2", text: "Rechnung als bezahlt markieren"
    assert_text "Betrag: 100,00"
    assert_no_field "Erhaltener Betrag in Euro"
    assert_no_button "Buchungsart ändern"
    assert_no_field "Beschreibung"
    fill_in "Datum des Zahlungseingangs", with: (Date.current - 1).strftime("%d.%m.%Y")
    select "Privatkonto", from: "Zahlungsart"
    click_button "Rechnung als bezahlt markieren"
    assert_no_selector "dialog[open]"
    assert_current_path invoices_path
    assert_equal "invoice_#{@invoice.id}", URI.parse(page.current_url).fragment
    within "#invoice_#{@invoice.id}" do
      assert_text "Bezahlt"
      assert_text "100,00 €"
      assert_no_link "Als bezahlt markieren"
    end
    assert page.evaluate_script("document.querySelector(':target')?.getBoundingClientRect().top >= 0")
    payment = @invoice.reload.payment_entry
    assert_equal Date.current - 1, payment.paid_on
    assert_equal "private", payment.payment_account
    visit invoice_path(@invoice)
    within "[aria-label='Zahlungsstatus']" do
      assert_text "Bezahlt"
      assert_text "100,00 €"
      click_link "Zahlung in der EÜR bearbeiten"
    end
    assert_current_path edit_bookkeeping_entry_path(payment)
    click_button "Rechnung als bezahlt markieren"
    assert_equal 1, BookkeepingEntry.where(invoice_id: @invoice.id).count
  end

  test "short foreign payment form works on mobile" do
    page.current_window.resize_to(390, 844)
    foreign_invoice = @invoice.workspace.invoices.new(@invoice.attributes.except("id", "invoice_number", "created_at", "updated_at").merge(
      currency: "USD", exchange_rate: "0.9", exchange_rate_on: Date.current, exchange_rate_source: "Testkurs"))
    foreign_invoice.invoice_lines.build(description: "Beratung", quantity: 1, unit_price: 100, unit_code: "C62")
    foreign_invoice.save!
    @invoice = foreign_invoice
    visit invoices_path
    within "#invoice_#{@invoice.id}" do
      click_link "Als bezahlt markieren"
    end
    assert_selector "dialog[open]"
    within "dialog[open]" do
      assert_text "100,00 USD"
    end
    assert_field "Erhaltener Betrag in Euro", with: "90,00"
    fill_in "Erhaltener Betrag in Euro", with: "92,00"
    fill_in "Datum des Zahlungseingangs", with: (Date.current - 1).strftime("%d.%m.%Y")
    select "Privatkonto", from: "Zahlungsart"
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth && document.querySelector('dialog').scrollWidth <= document.querySelector('dialog').clientWidth"), "Zahlungsformular darf mobil nicht horizontal überlaufen"
    page.save_screenshot(Rails.root.join("tmp/screenshots/invoice-payment-mobile.png"))
    click_button "Rechnung als bezahlt markieren"
    assert_no_selector "dialog[open]"
    assert_current_path invoices_path
    assert_equal "invoice_#{@invoice.id}", URI.parse(page.current_url).fragment
    assert_selector "#invoice_#{@invoice.id}", text: "Bezahlt"
    assert page.evaluate_script("document.querySelector(':target')?.getBoundingClientRect().top < window.innerHeight")
    assert_equal 92, @invoice.reload.payment_entry.amount
    assert_equal "private", @invoice.payment_entry.payment_account
  ensure
    page.current_window.resize_to(1400, 1100)
  end

  test "payment popup can be cancelled with Escape and keeps validation errors inside" do
    visit invoices_path
    within "#invoice_#{@invoice.id}" do
      click_link "Als bezahlt markieren"
    end
    assert_selector "dialog[open]"
    find("dialog").send_keys(:escape)
    assert_no_selector "dialog[open]"
    within "#invoice_#{@invoice.id}" do
      click_link "Als bezahlt markieren"
    end
    within "dialog[open]" do
      fill_in "Datum des Zahlungseingangs", with: (Date.current + 1).strftime("%d.%m.%Y")
      click_button "Rechnung als bezahlt markieren"
      assert_selector "[role=alert]", text: "Zukunft"
      assert_field "Datum des Zahlungseingangs", with: (Date.current + 1).strftime("%d.%m.%Y")
      click_button "Abbrechen"
    end
    assert_no_selector "dialog[open]"
    assert_current_path invoices_path
    assert_nil @invoice.reload.payment_entry
  end

  test "existing income can settle an invoice from EÜR and deletion reopens it" do
    visit new_bookkeeping_entry_path(kind: "income")
    fill_in "Erhaltener Betrag in Euro", with: "100"
    fill_in "Beschreibung", with: "Kundenzahlung"
    click_button "Speichern"
    within "#income" do
      assert_text "100,00 €"
    end
    payment = BookkeepingEntry.order(:id).last
    visit edit_bookkeeping_entry_path(payment)
    select find("#bookkeeping_entry_invoice_id option[value='#{@invoice.id}']").text, from: "Zahlung zu einer Rechnung (optional)"
    assert_field "Beleg- oder Rechnungsnummer", with: @invoice.invoice_number
    click_button "Rechnung als bezahlt markieren"
    assert_link "Rechnung #{@invoice.invoice_number} · Bezahlt"
    assert @invoice.reload.payment_received?
    assert_equal payment.id, @invoice.payment_entry.id
    accept_confirm(/Zahlung löschen/) do
      within find("tr", text: "Rechnung #{@invoice.invoice_number} · Bezahlt") do
        click_button "Löschen"
      end
    end
    assert_no_selector "h2", text: "Rechnungen ohne erfassten Zahlungseingang"
    visit invoice_path(@invoice)
    assert_link "Als bezahlt markieren"
    assert_not @invoice.reload.payment_received?
  end
end
