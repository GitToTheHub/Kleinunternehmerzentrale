require "application_system_test_case"

class BookkeepingImportsSystemTest < ApplicationSystemTestCase
  test "ELSTER preparation has its own expanded page and retains the selected year" do
    visit bookkeeping_entries_path(year: 2025)
    click_link "EÜR für ELSTER vorbereiten"
    assert_current_path prepare_euer_bookkeeping_entries_path(year: 2025)
    assert_selector "h1", text: "EÜR für ELSTER vorbereiten"
    assert_selector "h2", text: "Zuordnung zur Anlage EÜR 2025"
    assert_no_selector "details", visible: :all
    click_link "Vollständige Anlage EÜR ansehen und ergänzen"
    assert_current_path edit_euer_statement_path(year: 2025)
    assert_no_selector "details", visible: :all
    assert_field "euer_details_taxpayer_name"
    visit prepare_euer_bookkeeping_entries_path(year: 2025)
    select "2026", from: "Kalenderjahr"
    assert_selector "h2", text: "Zuordnung zur Anlage EÜR 2026"
    click_link "Zur Buchhaltung"
    assert_current_path bookkeeping_entries_path(year: 2026)
  end

  test "user transfers EÜR totals checks preview and continues after cutoff" do
    visit bookkeeping_entries_path
    click_link "Bisherige Buchhaltung übernehmen"
    fill_in "Bisherige EÜR bis einschließlich", with: "29.09.2026"
    fill_in "Quelle / Bezeichnung", with: "sevdesk bis September"
    fill_in "import_amount_income_small", with: "1000,00"
    fill_in "import_amount_income_small_details", with: "300,00"
    assert_no_selector "[name^='bookkeeping_import[details]']", visible: :all
    fill_in "import_amount_expense_meals", with: "70,00"
    fill_in "import_amount_deposits", with: "200,00"
    fill_in "import_amount_withdrawals", with: "300,00"
    within "[data-bookkeeping-import-target=totals]" do
      assert_text "1.000,00 €"
      assert_text "70,00 €"
      assert_text "930,00 €"
      assert_text "200,00 €"
      assert_text "300,00 €"
    end
    within "section.bookkeeping-import-group", text: "Betriebseinnahmen" do
      assert_selector "[data-key=income][data-bookkeeping-import-target=sum]", text: "1.000,00 €"
    end
    click_button "Übernahme prüfen"
    assert_selector "h1", text: "Übernahme prüfen"
    assert_selector "dd strong", text: "930,00 €"
    assert_equal 0, BookkeepingImport.count
    find("summary", text: "Vollständigen EÜR-Vordruck mit berechneten Summen anzeigen").click
    within "tr[data-euer-line='13']" do
      assert_text "300,00 €"
    end
    within "tr[data-euer-line='98']" do
      assert_text "930,00 €"
    end
    check "Ich habe die Summen mit meiner bisherigen EÜR abgeglichen. Der Zeitraum ist vollständig berücksichtigt und wird hier nicht zusätzlich einzeln erfasst."
    click_button "EÜR-Summen übernehmen"
    assert_text "Die bisherigen EÜR-Summen wurden übernommen."
    assert_text "Neue Vorgänge erfasst du ab 30.09.2026"
    assert_selector "dd strong", text: "930,00 €"
    visit edit_euer_statement_path(year: 2026)
    assert_selector "h1", text: "Vollständige Anlage EÜR 2026"
    within "tr[data-euer-line='13']" do
      click_link "Ergänzen"
    end
    assert_field "EÜR-Position", with: "income_small_details"
    fill_in "Zusätzlicher Betrag in Euro", with: "25"
    select "2025", from: "Steuerjahr"
    assert_selector "#euer_adjustment_field_key option[value=expense_goods]", text: "Zeile 27", visible: :all
    select "2026", from: "Steuerjahr"
    assert_selector "#euer_adjustment_field_key option[value=expense_goods]", text: "Zeile 29", visible: :all
    assert_field "Zusätzlicher Betrag in Euro", with: "25"
    visit edit_euer_statement_path(year: 2026)
    fill_in "euer_details_taxpayer_name", with: "Mein Betrieb"
    click_button "Betriebsangaben speichern"
    assert_text "EÜR-Betriebsangaben gespeichert"
    assert_text "Mein Betrieb"
    page.execute_script("arguments[0].scrollIntoView({block: 'start', behavior: 'instant'})", find("tr[data-euer-line='12']"))
    page.save_screenshot(Rails.root.join("tmp/screenshots/complete-euer-desktop.png"))
    page.current_window.resize_to(390, 844)
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    page.execute_script("arguments[0].scrollIntoView({block: 'start', behavior: 'instant'})", find("tr[data-euer-line='12']"))
    page.save_screenshot(Rails.root.join("tmp/screenshots/complete-euer-mobile.png"))
    page.current_window.resize_to(1400, 1100)
    visit bookkeeping_entries_path(year: 2026)
    click_link "Übernahme ansehen"
    assert_selector "h1", text: "Übernommene EÜR-Summen"
    accept_confirm do
      click_button "Übernahme entfernen"
    end
    assert_text "Die Übernahme wurde entfernt"
    assert_equal 0, BookkeepingImport.count
  end

  test "CSV mode uses upload and the form fits a phone" do
    visit new_bookkeeping_import_path
    fill_in "import_amount_income_small", with: "123,45"
    assert_selector "label[for=import_amount_expense_it]", text: "Zeile 51", visible: :all
    assert_selector "#import_amount_expense_livestock_reserve:enabled", visible: :all
    select "2025", from: "Steuerjahr"
    assert_selector "[data-bookkeeping-import-target=sourceNote]", text: "Formulargrundlage: amtliche Anlage EÜR 2025."
    assert_selector "#import_amount_expense_livestock_reserve:disabled", visible: :all
    assert_selector "label[for=import_amount_expense_it]", text: "Zeile 50", visible: :all
    assert_selector "label[for=import_amount_iab_add_1]", text: "aus 2024", visible: :all
    assert_field "import_amount_income_small", with: "123,45"
    select "2026", from: "Steuerjahr"
    assert_selector "label[for=import_amount_expense_it]", text: "Zeile 51", visible: :all
    assert_selector "[data-bookkeeping-import-target=sourceNote]", text: "Formulargrundlage: amtliche Anlage EÜR 2026."
    assert_selector "label[for=import_amount_iab_add_1]", text: "aus 2025", visible: :all
    page.current_window.resize_to(390, 844)
    select "CSV mit EÜR-Summen hochladen", from: "Wie möchtest du die Summen übernehmen?"
    assert_selector "input[type=file]:enabled:required"
    assert_no_selector "#import_amount_income_small"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    select "Summen aus meiner EÜR eintragen", from: "Wie möchtest du die Summen übernehmen?"
    assert_selector "#import_amount_income_small:enabled"
    assert_no_selector "input[type=file]"
    assert_field "import_amount_income_small", with: "123,45"
    page.execute_script("arguments[0].scrollIntoView({block: 'start', behavior: 'instant'})", find("label[for=import_amount_income_small]"))
    page.save_screenshot(Rails.root.join("tmp/screenshots/euer-import-original-labels-mobile.png"))
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
  ensure
    page.current_window.resize_to(1440, 1100)
  end
end
