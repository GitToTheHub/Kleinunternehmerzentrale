require "application_system_test_case"

class BillingUnitsTest < ApplicationSystemTestCase
  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.current_window.resize_to(1400, 1100)
  end

  test "failed saving keeps the popover open and shows an error" do
    visit new_invoice_path
    assert_equal InvoicesHelper::FIELD_ICON_PATHS.fetch(:settings), first(".unit-settings svg path")[:d]
    page.execute_script <<~JS
      const originalFetch = window.fetch;
      window.fetch = (url, options) => String(url) === #{workflow_path.to_json}
        ? Promise.resolve(new Response(JSON.stringify({ error: "Fehler" }), { status: 503 }))
        : originalFetch(url, options);
    JS
    first("button[aria-label='Positionseinheiten ändern']").click
    within "#billing-units" do
      click_button "Einheiten speichern"
      assert_text "Die Einheiten konnten nicht gespeichert werden. Bitte versuche es erneut."
      assert_button "Einheiten speichern", disabled: false
    end
    find("#billing-units button", text: "Einheiten speichern").send_keys(:escape)
    assert_no_selector "#billing-units", visible: true
  end

  test "an old hourly draft only offers the currently enabled units" do
    visit new_invoice_path
    first("button[aria-label='Positionseinheiten ändern']").click
    within "#billing-units" do
      uncheck "Stück"
      uncheck "Stunde"
      uncheck "Tag"
      click_button "Einheiten speichern"
    end
    assert_text "Einheiten gespeichert. Die Auswahl wurde aktualisiert."
    draft = Workspace.order(:id).last.invoice_drafts.create!(data: {
      "invoice_lines_attributes" => { "0" => { "description" => "Alter Entwurf", "quantity" => "3", "unit_price" => "85", "unit_code" => "HUR", "tax_rate" => "0" } }
    })
    visit edit_draft_invoices_path(draft_id: draft.id)
    within "[data-invoice-lines-target='row']" do
      assert_select "Einheit", selected: "Monat", options: [ "Monat", "Pauschal" ]
      assert_field "Monate", with: "3,0"
      assert_field "Preis pro Monat", with: "85,00"
    end
    click_button "Position hinzufügen"
    within all("[data-invoice-lines-target='row']").last do
      assert_select "Einheit", selected: "Monat", options: [ "Monat", "Pauschal" ]
    end
  end

  test "units update immediately in the draft on mobile and persist" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    visit new_invoice_path
    within "[data-invoice-lines-target='row']" do
      fill_in "Titel", with: "Meine Leistung"
      fill_in "Stunden", with: "3"
      fill_in "Preis pro Stunde", with: "85"
    end
    first("button[aria-label='Positionseinheiten ändern']").click
    within "#billing-units" do
      InvoiceLine::UNIT_CODES.each_value { |label| assert_checked_field label }
      uncheck "Stunde"
      uncheck "Tag"
      uncheck "Monat"
      uncheck "Pauschal"
      click_button "Einheiten speichern"
    end
    assert_text "Einheiten gespeichert. Die Auswahl wurde aktualisiert."
    assert_no_selector "#billing-units", visible: true
    within "[data-invoice-lines-target='row']" do
      assert_field "Titel", with: "Meine Leistung"
      assert_field "Menge", with: "3"
      assert_field "Preis pro Stück", with: "85,00"
      assert_select "Einheit", selected: "Stück", options: [ "Stück" ]
    end
    click_button "Position hinzufügen"
    within all("[data-invoice-lines-target='row']").last do
      assert_select "Einheit", selected: "Stück", options: [ "Stück" ]
    end
    first("button[aria-label='Positionseinheiten ändern']").click
    within "#billing-units" do
      uncheck "Stück"
      click_button "Einheiten speichern"
      assert_text "Wähle mindestens eine gültige Einheit."
      check "Tag"
      click_button "Einheiten speichern"
    end
    assert_text "Einheiten gespeichert. Die Auswahl wurde aktualisiert."
    all("[data-invoice-lines-target='row']").each do |row|
      within row do
        assert_select "Einheit", selected: "Tag", options: [ "Tag" ]
        assert_field "Preis pro Tag"
      end
    end
    first("button[aria-label='Positionseinheiten ändern']").click
    within "#billing-units" do
      assert_checked_field "Tag"
      page.save_screenshot(Rails.root.join("tmp/screenshots/billing-units.png"))
      find("button[aria-label='Schließen']").click
    end
    assert_no_selector "#billing-units", visible: true
    page.refresh
    first("button[aria-label='Positionseinheiten ändern']").click
    within "#billing-units" do
      assert_checked_field "Tag"
      assert_unchecked_field "Stück"
      assert_unchecked_field "Stunde"
    end
  end

  test "disabling piece hour and day switches hours to month and supports flat rate" do
    visit new_invoice_path
    within "[data-invoice-lines-target='row']" do
      fill_in "Stunden", with: "3"
      fill_in "Preis pro Stunde", with: "85"
    end
    first("button[aria-label='Positionseinheiten ändern']").click
    within "#billing-units" do
      uncheck "Stück"
      uncheck "Stunde"
      uncheck "Tag"
      click_button "Einheiten speichern"
    end
    within "[data-invoice-lines-target='row']" do
      assert_select "Einheit", selected: "Monat", options: [ "Monat", "Pauschal" ]
      assert_field "Monate", with: "3"
      assert_field "Preis pro Monat", with: "85,00"
    end
    first("button[aria-label='Positionseinheiten ändern']").click
    within "#billing-units" do
      uncheck "Monat"
      click_button "Einheiten speichern"
    end
    within "[data-invoice-lines-target='row']" do
      assert_select "Einheit", selected: "Pauschal", options: [ "Pauschal" ]
      assert_no_field "Monate"
      assert_field "Pauschalpreis", with: "85,00"
    end
    assert_selector "[data-invoice-lines-target='total']", text: "85,00"
  end
end
