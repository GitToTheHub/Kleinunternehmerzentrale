require "application_system_test_case"

class EverydayBookkeepingSystemTest < ApplicationSystemTestCase
  test "equipment purchases have their own entry option leading directly to the asset form" do
    visit new_bookkeeping_entry_path
    assert_no_difference [ "BookkeepingEntry.count", "BusinessAsset.count" ] do
      click_link "Anlagegut erfassen"
      assert_current_path new_business_asset_path
      assert_field "Bezeichnung des Anlageguts"
    end
  end

  test "booking starts on its own page and selecting a type reveals the correct form" do
    visit bookkeeping_entries_path
    click_link "Neue Buchung"
    assert_current_path new_bookkeeping_entry_path
    assert_selector ".booking-groups .booking-type-group", count: 2
    assert_no_select "Art des Vorgangs"
    assert_no_button "Speichern"
    click_button "Buchungsart ändern" if page.has_button?("Buchungsart ändern", wait: 0)
    choose "bookkeeping_entry_kind_expense"
    assert_field "Gezahlter Betrag in Euro"
    assert_no_selector ".booking-groups .booking-type-group"
    assert_selector "[data-euer-entry-target=kindLabel]", text: "Ausgabe"
    fill_in "Gezahlter Betrag in Euro", with: "100"
    fill_in "Beschreibung", with: "Umbuchung zur Einlage"
    assert_selector ".booking-kind-description", text: BookkeepingEntriesHelper::BOOKING_ACTIONS.fetch("expense").fetch(:hint)
    click_button "Buchungsart ändern"
    find("#bookkeeping_entry_kind_expense").find(:xpath, "ancestor::label").click
    assert_no_selector ".booking-groups .booking-type-group"
    assert_field "Gezahlter Betrag in Euro", with: "100"
    assert_field "Beschreibung", with: "Umbuchung zur Einlage"
    click_button "Buchungsart ändern" if page.has_button?("Buchungsart ändern", wait: 0)
    choose "bookkeeping_entry_kind_deposit"
    assert_no_select "bookkeeping_entry_category"
    assert_field "Eingelegter Betrag in Euro", with: "100"
    assert_no_selector ".booking-groups .booking-type-group"
    assert_selector "[data-euer-entry-target=kindLabel]", text: "Private Geldeinlage"
    assert_selector ".booking-kind-description", text: BookkeepingEntriesHelper::BOOKING_ACTIONS.fetch("deposit").fetch(:hint)
    click_button "Buchungsart ändern"
    assert_selector ".booking-groups .booking-type-group", count: 2
    click_button "Auswahl schließen"
    assert_no_selector ".booking-groups .booking-type-group"
    assert_field "Beschreibung", with: "Umbuchung zur Einlage"
    page.current_window.resize_to(390, 844)
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    page.save_screenshot(Rails.root.join("tmp/screenshots/booking-type-selection-mobile.png"))
    click_button "Speichern"
    assert_text "Vorgang gespeichert."
    assert_equal "deposit", BookkeepingEntry.order(:id).last.kind
    within "#deposit" do
      assert_text "Umbuchung zur Einlage"
      assert_text "100,00 €"
    end
  ensure
    page.current_window.resize_to(1400, 1100)
  end

  test "mixed expense is recorded directly and included in the annual overview" do
    visit bookkeeping_entries_path(year: 2026)
    assert_no_button "Jahr anzeigen"
    select "2025", from: "Kalenderjahr"
    assert_selector ".bookkeeping-overview h2", text: "Deine Übersicht 2025"
    assert_current_path bookkeeping_entries_path(year: 2025)
    select "2026", from: "Kalenderjahr"
    assert_selector ".bookkeeping-overview h2", text: "Deine Übersicht 2026"
    assert_selector ".bookkeeping-overview dd strong", text: "0,00 €"
    click_link "Neue Buchung"
    choose "bookkeeping_entry_kind_expense"
    select_expense("expense_phone")
    fill_in "Beschreibung", with: "Telefon / Internet"
    check "Diese Ausgabe ist teilweise privat"
    fill_in "Gezahlter Betrag in Euro", with: "20"
    fill_in "Wie viel Prozent nutzt du betrieblich?", with: "60"
    fill_in "Wie hast du den Anteil ermittelt?", with: "Auswertung der Telefonate Januar bis März"
    select "Privatkonto / privat bezahlt", from: "Bezahlt von"
    assert_text "12,00 € betrieblich, 8,00 € privat"
    assert_text "12,00 € werden zusätzlich als Einlage berücksichtigt"
    page.current_window.resize_to(390, 844)
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    page.save_screenshot(Rails.root.join("tmp/screenshots/everyday-expense-mobile.png"))
    click_button "Speichern"
    assert_text "Vorgang gespeichert."
    within "#deposit" do
      assert_text "12,00"
      assert_link "Ursprung bearbeiten"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/everyday-payments-mobile.png"))
    assert_selector "h1", text: "Meine Buchhaltung"
    assert_selector "dd strong", text: "-12,00 €"
    click_link "EÜR für ELSTER vorbereiten"
    assert_link "EÜR als CSV"
    page.save_screenshot(Rails.root.join("tmp/screenshots/everyday-annual-mobile.png"))
  ensure
    page.current_window.resize_to(1400, 1100)
  end

  test "additional expense choices remain accessible without losing the current selection" do
    visit new_bookkeeping_entry_path(kind: "expense")
    assert_selector "#expense-area-cards"
    assert_no_button "Häufige Zahlungsarten anzeigen"
    select_expense("expense_phone")
    select_expense("expense_meals")
    assert_field "Steuerlich abziehbarer Anteil in Prozent (optional)"
    assert_select "bookkeeping_entry_category", selected: expense_position("expense_meals"), visible: :all
    click_button "Buchungsart ändern" if page.has_button?("Buchungsart ändern", wait: 0)
    choose "bookkeeping_entry_kind_deposit"
    assert_no_select "bookkeeping_entry_category"
    assert_no_field "Wie viel Prozent nutzt du betrieblich?"
  end
  test "private use is maintained on the asset and offsets annual depreciation" do
    visit new_business_asset_path
    fill_in "Bezeichnung des Anlageguts", with: "Gemischt genutzter Mac"
    fill_in "Steuerliche Anschaffungskosten / Einlagewert in Euro", with: "1200"
    fill_in "business_asset_acquired_on_display", with: "01.01.2026"
    fill_in "business_asset_paid_on_display", with: "01.01.2026"
    find("summary", text: "Private Mitnutzung", exact_text: true).click
    within all(".asset-private-use-row").first do
      fill_in "Nutzungsjahr", with: "2026"
      fill_in "Betriebliche Nutzung in diesem Jahr (%)", with: "60"
      fill_in "Wie hast du die Nutzung für dieses Jahr ermittelt?", with: "Nutzungsaufzeichnungen"
      select "Fachlich ermittelten Jahreswert verwenden", from: "Private Nutzung berücksichtigen"
      fill_in "Fachlich ermittelter Privatnutzungswert in Euro", with: "200"
      select "Privaten Anteil der Abschreibung berechnen", from: "Private Nutzung berücksichtigen"
      assert_no_field "Fachlich ermittelter Privatnutzungswert in Euro"
    end
    click_button "Weiteres Nutzungsjahr hinzufügen"
    within all(".asset-private-use-row").last do
      fill_in "Nutzungsjahr", with: "2027"
      fill_in "Betriebliche Nutzung in diesem Jahr (%)", with: "80"
      fill_in "Wie hast du die Nutzung für dieses Jahr ermittelt?", with: "Neue Nutzungsaufzeichnungen"
    end
    click_button "Anlagegut speichern"
    assert_text "Anlagegut gespeichert"
    asset = BusinessAsset.find_by!(name: "Gemischt genutzter Mac")
    assert_equal 160, asset.private_use_for(2026).amount
    assert_equal 80, asset.private_use_for(2027).amount
    visit edit_business_asset_path(asset)
    assert_text "160,00 €"
    page.execute_script("arguments[0].scrollIntoView({block: 'start', behavior: 'instant'})", find("summary", text: "Private Mitnutzung", exact_text: true))
    page.save_screenshot(Rails.root.join("tmp/screenshots/asset-private-use.png"))
    page.current_window.resize_to(390, 844)
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    page.execute_script("arguments[0].scrollIntoView({block: 'start', behavior: 'instant'})", find("summary", text: "Private Mitnutzung", exact_text: true))
    page.save_screenshot(Rails.root.join("tmp/screenshots/asset-private-use-mobile.png"))
    page.current_window.resize_to(1400, 1100)
    visit bookkeeping_entries_path(year: 2026)
    within ".bookkeeping-overview" do
      assert_text "160,00 €"
      assert_text "400,00 €"
      assert_text "-240,00 €"
    end
    assert_text "60.0 % betrieblich"
  end
end
