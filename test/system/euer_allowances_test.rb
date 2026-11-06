require "application_system_test_case"

class EuerAllowancesSystemTest < ApplicationSystemTestCase
  def business
    visit edit_euer_statement_path(year: 2026)
    fill_in "euer_details_taxpayer_name", with: "Beispiel"
    fill_in "euer_details_first_name", with: "Erika"
    fill_in "euer_details_legal_form", with: "Einzelunternehmen"
    select "Selbständige Arbeit", from: "euer_details_income_type"
    click_button "Betriebsangaben speichern"
    assert_text "EÜR-Betriebsangaben gespeichert"
    workspace = EuerStatement.last.workspace
    workspace.bookkeeping_entries.create!(kind: "income", category: "income_small", paid_on: "2026-06-01", amount: 10_000, description: "Jahreseinnahmen")
    workspace.bookkeeping_entries.create!(kind: "expense", category: "expense_other", paid_on: "2026-06-01", amount: 100, description: "Betriebliche Kosten")
    workspace
  end

  test "annual election replaces costs and home days calculate without double counting" do
    workspace = business
    visit prepare_euer_bookkeeping_entries_path(year: 2026)
    click_link "Ausgabenmethode vergleichen und wählen"
    select "Hauptberuflich schriftstellerisch oder journalistisch", from: "euer_expense_policy_deduction_method"
    check "euer_expense_policy_eligibility_confirmed"
    click_button "Ausgabenmethode speichern"
    assert_text "3.000,00 €"
    visit bookkeeping_entries_path(year: 2026)
    assert_selector "dd strong", text: "7.000,00 €"
    assert_equal 100, workspace.bookkeeping_entries.find_by!(kind: "expense").amount
    visit edit_euer_expense_policy_path(year: 2026)
    select "Tatsächliche Betriebsausgaben", from: "euer_expense_policy_deduction_method"
    select "Tagespauschale für Arbeit zuhause", from: "euer_expense_policy_home_office_method"
    assert_no_selector "#euer_expense_policy_home_months:enabled"
    fill_in "Berücksichtigungsfähige Tage zuhause", with: "50"
    fill_in "Dokumentation der Tage oder Monate", with: "Datierte Liste mit 50 Tagen"
    check "euer_expense_policy_home_eligibility_confirmed"
    click_button "Ausgabenmethode speichern"
    assert_text "300,00 €"
    visit bookkeeping_entries_path(year: 2026)
    assert_selector "dd strong", text: "9.600,00 €"
    assert_equal 2, workspace.bookkeeping_entries.count
    page.current_window.resize_to(390, 1000)
    visit edit_euer_expense_policy_path(year: 2026)
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    page.save_screenshot(Rails.root.join("tmp/screenshots/euer-allowances-mobile.png"))
  ensure
    page.current_window.resize_to(1400, 1100)
  end

  test "daycare periods and reserve slots are captured and their result is included once" do
    workspace = business
    visit edit_euer_expense_policy_path(year: 2026)
    select "Selbständige Kindertagespflege", from: "euer_expense_policy_deduction_method"
    click_button "Betreuungszeitraum hinzufügen"
    within first("[data-euer-expense-policy-target=childcareRow]") do
      fill_in "Anonymes Kind- oder Platzkürzel", with: "Kind A"
      fill_in "Vereinbarte Wochenstunden", with: "40"
    end
    click_button "Betreuungszeitraum hinzufügen"
    within all("[data-euer-expense-policy-target=childcareRow]").last do
      fill_in "Anonymes Kind- oder Platzkürzel", with: "Platz 1"
      select "Freihalteplatz", from: "Art des Platzes"
      assert_no_selector "[data-childcare-regular] input:enabled"
      fill_in "Belegte Tage je Monat", with: "0"
      fill_in "Betreuungsstunden je belegtem Tag", with: "0"
    end
    check "euer_expense_policy_eligibility_confirmed"
    check "euer_expense_policy_daycare_eligibility_confirmed"
    click_button "Ausgabenmethode speichern"
    assert_text "5.400,00 €"
    assert_equal 2, workspace.euer_expense_policies.sole.daycare_rows.size
    visit bookkeeping_entries_path(year: 2026)
    assert_selector "dd strong", text: "4.600,00 €"
    visit edit_euer_expense_policy_path(year: 2026)
    assert_selector "[data-euer-expense-policy-target=childcareRow]", count: 2
    within first("[data-euer-expense-policy-target=childcareRow]") do
      click_button "Zeitraum entfernen"
    end
    click_button "Ausgabenmethode speichern"
    assert_text "600,00 €"
    assert_equal 1, workspace.euer_expense_policies.sole.daycare_rows.size
  end
end
