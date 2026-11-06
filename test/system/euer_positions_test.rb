require "application_system_test_case"

class EuerPositionsSystemTest < ApplicationSystemTestCase
  test "expense cards collapse after choosing and allow reselecting or changing the area and type" do
    visit new_bookkeeping_entry_path(kind: "expense")
    assert_selector "#expense-area-cards .booking-type-option", count: 9
    assert_no_field "Datum des Zahlungsausgangs"
    assert_no_select "Bereich"
    assert_no_select "Ausgabenart"
    fill_in "Gezahlter Betrag in Euro", with: "12,50"
    fill_in "Beschreibung", with: "VPS"
    find("#expense-area-cards input[value='Telefon, Internet und EDV']").find(:xpath, "ancestor::label").click
    assert_no_selector "#expense-type-cards input:checked"
    assert_no_selector "#expense-type-cards input:focus"
    assert_no_selector "#expense-type-cards .booking-type-option:has(input:focus-visible)"
    find("#expense-type-cards input[value='expense_it']").find(:xpath, "ancestor::label").click
    assert_field "Datum des Zahlungsausgangs"
    assert_no_selector "#expense-area-cards"
    assert_no_selector "#expense-type-cards"
    assert_text "Ausgabenbereich: Telefon, Internet und EDV"
    assert_text "Ausgabenart: Laufende EDV-Kosten"
    click_button "Ausgabenart ändern"
    assert_selector "#expense-type-cards .booking-type-option", count: 2
    find("#expense-type-cards input[value='expense_it']").find(:xpath, "ancestor::label").click
    assert_no_selector "#expense-type-cards"
    click_button "Ausgabenbereich ändern"
    find("#expense-area-cards input[value='Telefon, Internet und EDV']").find(:xpath, "ancestor::label").click
    assert_no_selector "#expense-area-cards"
    assert_text "Ausgabenart: Laufende EDV-Kosten"
    select_expense("expense_goods")
    find(".expense-search summary").click
    fill_in "Was möchtest du buchen?", with: "VPS"
    find(".expense-search-result", text: "Laufende EDV-Kosten").click
    assert_text "Ausgabenart: Laufende EDV-Kosten"
    assert_no_selector "#expense-area-cards"
    assert_no_selector "#expense-type-cards"
    assert_field "Gezahlter Betrag in Euro", with: "12,50"
    click_button "Speichern"
    assert_text "Vorgang gespeichert."
    entry = BookkeepingEntry.order(:id).last
    assert_equal "expense_it", entry.category
    visit edit_bookkeeping_entry_path(entry)
    assert_no_selector "#expense-area-cards"
    assert_no_selector "#expense-type-cards"
    assert_text "Ausgabenart: Laufende EDV-Kosten"
    click_button "Buchungsart ändern"
    choose "bookkeeping_entry_kind_deposit"
    click_button "Buchungsart ändern"
    choose "bookkeeping_entry_kind_expense"
    assert_selector "#expense-area-cards input[value='Telefon, Internet und EDV']"
    page.save_screenshot(Rails.root.join("tmp/screenshots/expense-cards.png"))
    page.driver.browser.manage.window.resize_to(390, 844)
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
  end
end
