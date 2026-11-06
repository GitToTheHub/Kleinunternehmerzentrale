require "application_system_test_case"

class ExpenseSearchSystemTest < ApplicationSystemTestCase
  test "search suggests categories and keeps the draft intact until explicit selection" do
    visit new_bookkeeping_entry_path(kind: "expense")
    assert_no_field "Was möchtest du buchen?"
    assert_selector "#expense-area-cards"
    find(".expense-search summary", text: "Hilfe bei der Zuordnung").click
    fill_in "Gezahlter Betrag in Euro", with: "12,50"
    fill_in "Beschreibung", with: "Meine Serverrechnung"
    fill_in "Was möchtest du buchen?", with: "VPS bei IONOS"
    assert_selector ".expense-search-result", text: "Laufende EDV-Kosten"
    assert_no_select "bookkeeping_entry_category"
    assert_no_difference "BookkeepingEntry.count" do
      find(".expense-search-result", text: "Laufende EDV-Kosten").click
      assert_field "bookkeeping_entry_category", with: "expense_it", visible: :all
      assert_field "Gezahlter Betrag in Euro", with: "12,50"
      assert_field "Beschreibung", with: "Meine Serverrechnung"
    end
    fill_in "Was möchtest du buchen?", with: "unbekanntxyz"
    assert_text "Kein passender Treffer"
    assert_no_selector ".expense-search-result"
    assert_field "bookkeeping_entry_category", with: "expense_it", visible: :all
    select_expense("expense_supplies")
    assert_field "bookkeeping_entry_category", with: "expense_supplies", visible: :all
    click_button "Buchungsart ändern"
    choose "bookkeeping_entry_kind_income"
    assert_no_field "Was möchtest du buchen?"
    click_button "Buchungsart ändern"
    choose "bookkeeping_entry_kind_expense"
    assert_no_field "Was möchtest du buchen?"
    find(".expense-search summary").click
    assert_field "Was möchtest du buchen?", with: ""
  end

  test "AppleCare suggests insurance with a mixed use note and clears the note on another search" do
    visit new_bookkeeping_entry_path(kind: "expense")
    assert_no_field "Was möchtest du buchen?"
    assert_selector "#expense-area-cards"
    find(".expense-search summary", text: "Hilfe bei der Zuordnung").click
    fill_in "Was möchtest du buchen?", with: "Apple Care+ für mein iPhone"
    assert_text "berücksichtige nur den betrieblichen Anteil"
    assert_no_select "bookkeeping_entry_category"
    find(".expense-search-result", text: "Beiträge, Gebühren, Abgaben und Versicherungen").click
    assert_field "bookkeeping_entry_category", with: "expense_insurance", visible: :all
    fill_in "Was möchtest du buchen?", with: "Telefonrechnung"
    assert_no_text "berücksichtige nur den betrieblichen Anteil"
  end

  test "equipment question distinguishes own use and resale and resets after editing" do
    visit new_bookkeeping_entry_path(kind: "expense")
    assert_no_field "Was möchtest du buchen?"
    assert_selector "#expense-area-cards"
    find(".expense-search summary", text: "Hilfe bei der Zuordnung").click
    fill_in "Was möchtest du buchen?", with: "Computer"
    assert_text "Wofür hast du den Gegenstand gekauft?"
    click_button "Für meinen Betrieb nutzen"
    assert_link "Anlagegut erfassen", href: new_business_asset_path
    assert_no_select "bookkeeping_entry_category"
    click_button "Zum Weiterverkauf"
    assert_no_selector "[data-expense-search-target=own]:not([hidden])"
    click_button "Waren und Material auswählen"
    assert_field "bookkeeping_entry_category", with: "expense_goods", visible: :all
    fill_in "Was möchtest du buchen?", with: "Telefonrechnung"
    assert_no_button "Waren und Material auswählen"
    assert_no_button "Zum Weiterverkauf"
    find(".expense-search-result", text: "Aufwendungen für Telekommunikation").click
    assert_field "bookkeeping_entry_category", with: "expense_phone", visible: :all
    page.save_screenshot(Rails.root.join("tmp/screenshots/expense-search.png"))
    page.driver.browser.manage.window.resize_to(390, 844)
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
  end
end
