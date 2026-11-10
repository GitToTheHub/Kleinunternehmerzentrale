require "application_system_test_case"

class EuerBookkeepingTest < ApplicationSystemTestCase
  test "refund is recorded directly from its original expense" do
    visit new_bookkeeping_entry_path(kind: "income")
    click_button "Buchungsart ändern" if page.has_button?("Buchungsart ändern", wait: 0)
    choose "bookkeeping_entry_kind_expense"
    select_expense("expense_other")
    fill_in "Gezahlter Betrag in Euro", with: "100"
    fill_in "Beschreibung", with: "Zurückgegebene Ware"
    click_button "Speichern"
    within "tr", text: "Zurückgegebene Ware" do
      click_link "Erstattung erfassen"
    end
    assert_selector "h1", text: "Erstattung erfassen"
    assert_no_select "Art des Vorgangs"
    assert_no_select "Steuerliche Kategorie"
    fill_in "Zurückgezahlter Betrag in Euro", with: "40"
    assert page.evaluate_script("document.querySelector('form').checkValidity()"), page.evaluate_script("Array.from(document.querySelectorAll(':invalid')).map(input => [input.id, input.validationMessage, input.value])").inspect
    find_button("Rückzahlung speichern").evaluate_script("this.scrollIntoView({block: 'center', behavior: 'instant'})")
    click_button "Rückzahlung speichern"
    assert_text "Rückzahlung gespeichert und in der EÜR berücksichtigt."
    assert_text "Zurückgezahlt: 40,00"
    assert_text "Rückzahlung zu: Zurückgegebene Ware"
    refund = BookkeepingEntry.order(:id).last
    assert refund.reversal?
    assert_equal 40, refund.amount
    assert_equal 60, refund.original_entry.refundable_amount
    click_link "Bearbeiten", href: edit_bookkeeping_entry_path(refund)
    assert_selector "h1", text: "Rückzahlung bearbeiten"
    assert_no_select "Art des Vorgangs"
    assert_current_path edit_bookkeeping_entry_path(refund)
    assert_selector ".date-picker--enhanced"
    assert_field "Zurückgezahlter Betrag in Euro", with: "40,00"
    fill_in "Zurückgezahlter Betrag in Euro", with: "50"
    find_button("Rückzahlung speichern").evaluate_script("this.scrollIntoView({block: 'center', behavior: 'instant'})")
    click_button "Rückzahlung speichern"
    assert_text "Vorgang aktualisiert."
    assert_equal 50, refund.reload.amount
  end

  test "category explanations show practical examples and prevent duplicate asset withdrawals" do
    visit new_bookkeeping_entry_path(kind: "income")
    within "#bookkeeping-category-help" do
      assert_text "Für deine normalen Einnahmen"
      assert_no_text "Eine Einkommensteuererstattung"
    end
    select EuerFields.selection_label("vat_refund"), from: "bookkeeping_entry_category"
    within "#bookkeeping-category-help" do
      assert_text "meist nicht"
      assert_text "Eine Einkommensteuererstattung gehört nicht in die EÜR"
      assert_text "Dienstleistung aus dem Ausland"
      assert_no_text "Für deine normalen Einnahmen"
    end
    select EuerFields.selection_label("asset_income"), from: "bookkeeping_entry_category"
    within "#bookkeeping-category-help" do
      assert_text "Computer, eine Maschine oder ein Firmenfahrzeug"
      assert_text "300 €"
      assert_text "Zahlungseingang nur einmal"
      assert_no_text "Übernimmst du ihn stattdessen privat"
      assert_selector "a[href='#{business_assets_path}']", text: "Anlageverzeichnis öffnen"
    end
    click_button "Buchungsart ändern" if page.has_button?("Buchungsart ändern", wait: 0)
    choose "bookkeeping_entry_kind_expense"
    assert_no_selector "[data-category='asset_income']"
    select_expense("vat_payment")
    within "#bookkeeping-category-help" do
      assert_text "Reverse Charge"
      assert_text "nicht zusätzlich erfasst"
    end
    click_button "Buchungsart ändern" if page.has_button?("Buchungsart ändern", wait: 0)
    choose "bookkeeping_entry_kind_deposit"
    assert_no_selector "#bookkeeping-category-help"
    click_button "Buchungsart ändern" if page.has_button?("Buchungsart ändern", wait: 0)
    choose "bookkeeping_entry_kind_income"
    within "#bookkeeping-category-help" do
      assert_text "Für deine normalen Einnahmen"
    end
  end

  test "entry labels and hints follow kind category private account and reversals" do
    visit new_bookkeeping_entry_path(kind: "income")
    assert_field "Erhaltener Betrag in Euro"
    assert_text "Verkaufst du Betriebsausstattung"
    assert_no_text "Kaufst du Betriebsausstattung"
    assert_no_text "Bewertungsgrundlage"
    assert_no_text "zusätzlich als Privatentnahme"
    select "Privatkonto", from: "Zahlungsart"
    assert_text "zusätzlich als Privatentnahme"
    assert_no_text "automatisch zu deinen Einlagen"

    click_button "Buchungsart ändern"
    assert_selector "[data-euer-entry-target=kindChoices]:not([hidden])"
    choose "bookkeeping_entry_kind_expense"
    assert_field "Gezahlter Betrag in Euro"
    assert_text "Kaufst du Betriebsausstattung"
    assert_no_text "Verkaufst du Betriebsausstattung"
    assert_text "automatisch zu deinen Einlagen"
    assert_no_text "zusätzlich als Privatentnahme"
    assert_no_text "70 %"
    select_expense("expense_meals")
    assert_text "70 % vorbelegt"
    select_expense("vat_payment")
    assert_no_text "70 %"
    assert_no_text "Kaufst du Betriebsausstattung"
    assert_text "Nur für Sonderfälle: Umsatzsteuer"

    click_button "Buchungsart ändern"
    assert_selector "[data-euer-entry-target=kindChoices]:not([hidden])"
    choose "bookkeeping_entry_kind_deposit"
    assert_field "Eingelegter Betrag in Euro"
    assert_field "Datum der Einlage"
    assert_no_text "Kaufst du Betriebsausstattung"
    assert_no_text "Verkaufst du Betriebsausstattung"
    assert_no_text "Nur für Sonderfälle: Umsatzsteuer"
    click_button "Buchungsart ändern"
    assert_selector "[data-euer-entry-target=kindChoices]:not([hidden])"
    choose "bookkeeping_entry_kind_withdrawal"
    assert_field "Entnommener Betrag in Euro"
    assert_field "Datum der Entnahme"
    click_button "Buchungsart ändern"
    assert_selector "[data-euer-entry-target=kindChoices]:not([hidden])"
    choose "bookkeeping_entry_kind_noncash_deposit"
    assert_field "Steuerlicher Einlagewert in Euro"
    assert_text "Hier erfasst du nur Waren und Verbrauchsmaterial"
    assert_no_text "Du kaufst Stoff"
    assert_no_selector "#bookkeeping_entry_reversal"
    click_button "Buchungsart ändern"
    assert_selector "[data-euer-entry-target=kindChoices]:not([hidden])"
    choose "bookkeeping_entry_kind_noncash_withdrawal"
    assert_field "Steuerlicher Entnahmewert in Euro"
    assert_text "Übernimmst du ein Anlagegut dauerhaft ins Privatvermögen"
    select "Private Fahrzeugnutzung", from: "bookkeeping_entry_category"
    assert_field "Steuerlicher Wert der privaten Fahrzeugnutzung in Euro"
    assert_no_text "Übernimmst du ein Anlagegut dauerhaft ins Privatvermögen"
  end

  test "private asset contribution and goods withdrawal flow through the annual EÜR" do
    visit new_business_asset_path
    assert_selector ".date-picker--enhanced", count: 4, visible: :all
    find("#business_asset_acquired_on_display").click
    assert_selector "#acquired_on-calendar"
    within "#acquired_on-calendar" do
      click_button "Heute"
    end
    assert_field "business_asset_acquired_on_display", with: Date.current.strftime("%d.%m.%Y")
    fill_in "Bezeichnung des Anlageguts", with: "Testcomputer"
    select "Aus Privatvermögen eingelegt", from: "Zugang"
    assert_no_selector "#business_asset_paid_on_display"
    fill_in "Steuerliche Anschaffungskosten / Einlagewert in Euro", with: "1200,00"
    date("business_asset_acquired_on", "2026-10-12")
    click_button "Anlagegut speichern"
    assert_selector "h1", text: "Dein Anlageverzeichnis"
    assert_text "Testcomputer"

    visit new_bookkeeping_entry_path(kind: "income")
    click_button "Buchungsart ändern" if page.has_button?("Buchungsart ändern", wait: 0)
    choose "bookkeeping_entry_kind_noncash_withdrawal"
    assert_no_selector "#bookkeeping_entry_payment_account"
    assert_no_selector "#bookkeeping_entry_deductible_percent"
    date("bookkeeping_entry_paid_on", "2026-10-12")
    fill_in "Steuerlicher Entnahmewert in Euro", with: "200,00"
    fill_in "Beschreibung / Bewertungsgrundlage", with: "Ware für private Verwendung"
    click_button "Speichern"
    assert_selector "h2", text: "Deine Übersicht 2026"
    assert_selector "dd strong", text: "100,00 €"
    find("summary", text: "Einlagen und Entnahmen ansehen").click
    assert_selector "dd", text: "1.200,00 €"
    click_link "EÜR für ELSTER vorbereiten"
    assert_text "Zeile 21"
    assert_text "Zeile 34"
    page.save_screenshot(Rails.root.join("tmp/screenshots/euer-2026-desktop.png"))
    page.driver.browser.manage.window.resize_to(390, 1000)
    assert_equal false, page.evaluate_script("document.documentElement.scrollWidth > innerWidth"), "page should fit mobile viewport"
    page.save_screenshot(Rails.root.join("tmp/screenshots/euer-2026-mobile.png"))
  end

  test "expense categories filter options and manual depreciation can add a second year" do
    visit new_bookkeeping_entry_path(kind: "income")
    assert_selector "#bookkeeping_entry_category option", count: BookkeepingEntry::SMALL_BUSINESS_CATEGORIES.fetch("income").size, visible: :all
    assert_no_selector "#bookkeeping_entry_category option[value='expense_meals']", visible: :all
    click_button "Buchungsart ändern" if page.has_button?("Buchungsart ändern", wait: 0)
    choose "bookkeeping_entry_kind_expense"
    assert_selector "#expense-area-cards"
    assert_no_selector "#bookkeeping_entry_category option[value='income_small']", visible: :all
    find("#expense-area-cards input[value='Telefon, Internet und EDV']").find(:xpath, "ancestor::label").click
    find("summary", text: "Besondere Abzugsregeln (bei Bedarf)").click
    assert_selector "#bookkeeping_entry_deductible_percent"
    assert_selector "#bookkeeping_entry_category option:checked", text: "Bitte wähle die Ausgabenart", visible: :all
    select_expense("expense_meals")
    click_button "Buchungsart ändern" if page.has_button?("Buchungsart ändern", wait: 0)
    choose "bookkeeping_entry_kind_income"
    assert_no_selector "#bookkeeping_entry_deductible_percent"
    assert_selector "#bookkeeping_entry_category option:checked", text: "Geld von Kunden für Leistungen oder Waren"
    assert_no_selector "#bookkeeping_entry_category option[disabled]", visible: :all
    assert_no_selector "#bookkeeping_entry_category option[value='expense_meals']", visible: :all
    click_button "Buchungsart ändern" if page.has_button?("Buchungsart ändern", wait: 0)
    choose "bookkeeping_entry_kind_noncash_withdrawal"
    assert_selector "#bookkeeping_entry_category option", count: 2, visible: :all
    click_button "Buchungsart ändern" if page.has_button?("Buchungsart ändern", wait: 0)
    choose "bookkeeping_entry_kind_deposit"
    assert_no_selector "#bookkeeping_entry_category"
    click_button "Buchungsart ändern" if page.has_button?("Buchungsart ändern", wait: 0)
    choose "bookkeeping_entry_kind_expense"
    assert_selector "#expense-area-cards"
    select_expense("expense_meals")

    visit new_business_asset_path
    fill_in "Bezeichnung des Anlageguts", with: "Testmaschine"
    fill_in "Steuerliche Anschaffungskosten / Einlagewert in Euro", with: "1200,00"
    date("business_asset_acquired_on", "2026-10-12")
    date("business_asset_paid_on", "2026-10-12")
    select "Jährliche Abschreibung selbst vorgeben", from: "Abschreibung"
    within all(".euer-depreciation-row").first do
      fill_in "Jahr", with: "2026"
      fill_in "AfA in Euro (ersetzt den Jahresbetrag)", with: "100"
      fill_in "Begründung / Rechtsgrundlage", with: "Geprüfte AfA"
    end
    click_button "Weiteres Jahr hinzufügen"
    assert_selector ".euer-depreciation-row", count: 2
    within all(".euer-depreciation-row").last do
      fill_in "Jahr", with: "2027"
      fill_in "AfA in Euro (ersetzt den Jahresbetrag)", with: "400"
      fill_in "Begründung / Rechtsgrundlage", with: "Folgejahr"
    end
    click_button "Anlagegut speichern"
    assert_selector "h1", text: "Dein Anlageverzeichnis"
    item = BusinessAsset.find_by!(name: "Testmaschine")
    assert_equal [ 2026, 2027 ], item.asset_depreciations.order(:year).pluck(:year)
    assert_equal 700, item.schedule(2027)[:closing]
  end

  private

  def date(id, value)
    fill_in "#{id}_display", with: value.split("-").reverse.join(".")
  end
end
