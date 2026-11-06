require "application_system_test_case"

class EuerPreparationSystemTest < ApplicationSystemTestCase
  test "business data guides preparation without blocking everyday bookkeeping" do
    visit bookkeeping_entries_path(year: 2026)
    assert_link "Neue Buchung"
    click_link "EÜR für ELSTER vorbereiten"
    within ".euer-preparation-check" do
      assert_text "Noch zu ergänzen oder zu klären"
    end
    click_link "Betriebsangaben ergänzen und prüfen"
    fill_in "euer_details_taxpayer_name", with: "Beispiel"
    fill_in "euer_details_first_name", with: "Erika"
    fill_in "euer_details_tax_number", with: "12/345/67890"
    fill_in "euer_details_activity", with: "Forstwirtschaft"
    fill_in "euer_details_legal_form", with: "Einzelunternehmen"
    select "Land- und Forstwirtschaft", from: "euer_details_income_type"
    select "Nein", from: "euer_details_property_disposal"
    click_button "Betriebsangaben speichern"
    within ".euer-preparation-check" do
      assert_text "Anlage LuF"
      assert_text "Vom Kalenderjahr abweichender Beginn"
      assert_text "keine Umsatzsteuerberechnung"
      assert_link "Zeile 27 · Bildung Rücklage Tierbewertung bei Land- und Forstwirten"
    end
    click_link "Zur EÜR-Vorbereitung"
    assert_no_selector "details", visible: :all
    within ".euer-preparation-check" do
      assert_text "Anlage LuF"
    end
    click_link "Zur Buchhaltung"
    click_link "Neue Buchung"
    assert_selector "h1", text: "Buchung erfassen"
    page.current_window.resize_to(390, 1000)
    visit prepare_euer_bookkeeping_entries_path(year: 2026)
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    page.save_screenshot(Rails.root.join("tmp/screenshots/euer-preparation-check-mobile.png"))
  ensure
    page.current_window.resize_to(1400, 1100)
  end
end
