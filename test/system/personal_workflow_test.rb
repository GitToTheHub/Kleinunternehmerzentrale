require "application_system_test_case"

class PersonalWorkflowTest < ApplicationSystemTestCase
  test "a freelancer enables mixed costs and records an expense" do
    visit new_bookkeeping_entry_path(kind: "expense")
    select_expense("expense_phone")
    fill_in "Gezahlter Betrag in Euro", with: "20"
    fill_in "Beschreibung", with: "congstar gemischt"
    check "Diese Ausgabe ist teilweise privat"
    fill_in "Wie viel Prozent nutzt du betrieblich?", with: "60"
    fill_in "Wie hast du den Anteil ermittelt?", with: "Telefonate ausgewertet, Januar bis März"
    select "Privatkonto / privat bezahlt", from: "Bezahlt von"
    click_button "Speichern"
    assert_text "Vorgang gespeichert."
    within "#expense" do
      assert_text "congstar gemischt"
      assert_text "12,00"
    end
    assert_selector "#deposit"
    assert_selector "#withdrawal"
    visit new_invoice_path
    assert_select "Einheit", options: InvoiceLine::UNIT_CODES.values
    assert_select "Währung"
    assert_select "invoice_buyer_country"
    page.save_screenshot(Rails.root.join("tmp/screenshots/personal-workflow-invoice.png"))
    within "[data-invoice-lines-target='row']" do
      select "Pauschal", from: "Einheit"
      assert_no_field "Stunden"
      assert_field "Pauschalpreis"
    end
  end
end
