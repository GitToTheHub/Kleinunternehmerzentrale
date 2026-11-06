require "test_helper"

class EverydayBookkeepingTest < ActionDispatch::IntegrationTest
  test "bookkeeping links to a separate expanded tax preparation page for the selected year" do
    assert_no_difference "Workspace.count" do
      get bookkeeping_entries_path(year: 2025)
      assert_select "h1", "Meine Buchhaltung"
      assert_select "section#income"
      assert_select "section#expense"
      assert_select ".bookkeeping-overview dt", "Einnahmen"
      assert_select ".bookkeeping-overview dt", "Ausgaben"
      assert_select ".bookkeeping-overview dt", "Gewinn / Verlust"
      assert_select ".bookkeeping-overview h2", "Deine Übersicht 2025"
      assert_select "a", text: "Jahresabschluss", count: 0
      assert_select "a", text: "Zahlungen im Alltag", count: 0
      assert_select "a.button[href='#{prepare_euer_bookkeeping_entries_path(year: 2025)}']", text: "EÜR für ELSTER vorbereiten"
      assert_select "#euer-vorbereitung", count: 0
      get prepare_euer_bookkeeping_entries_path(year: 2025)
      assert_response :success
      assert_select "h1", "EÜR für ELSTER vorbereiten"
      assert_select "details", count: 0
      assert_select "h2", "Zuordnung zur Anlage EÜR 2025"
      assert_select "a[href='#{bookkeeping_entries_path(year: 2025)}']", text: "Zur Buchhaltung"
      assert_select "a[href='#{bookkeeping_entries_path(year: 2025, format: :csv)}']"
      get annual_bookkeeping_path(year: 2025)
      assert_redirected_to bookkeeping_entries_path(year: 2025)
      get bookkeeping_entries_path(year: "wrong")
      assert_select ".bookkeeping-overview h2", "Deine Übersicht #{Date.current.year}"
    end
  end

  test "booking button opens grouped radio choices with an explicit type selection" do
    get bookkeeping_entries_path
    assert_select "a[href='#{new_bookkeeping_entry_path}']", text: "Neue Buchung"
    assert_select ".booking-groups", count: 0
    assert_no_difference "Workspace.count" do
      get new_bookkeeping_entry_path
      assert_select "h1", "Buchung erfassen"
      assert_select ".booking-groups a[href='#{new_business_asset_path}']", text: /Anlagegut erfassen/
      assert_select "small", text: /Eine Anschaffung wie Mac oder iPhone/, count: 0
      assert_select ".booking-groups .booking-type-group", count: 2
      assert_select "input[name='bookkeeping_entry[kind]'][type='radio']", count: 6
      assert_select ".booking-type-group", text: /Zwischen Privat und Betrieb/ do
        %w[deposit withdrawal noncash_deposit noncash_withdrawal].each do |kind|
          assert_select "input[name='bookkeeping_entry[kind]'][value='#{kind}']"
        end
      end
      assert_select "input[name='bookkeeping_entry[kind]'][checked]", count: 0
      assert_select ".booking-entry-fields[disabled][hidden]"
      assert_select "select[name='bookkeeping_entry[kind]']", count: 0
      BookkeepingEntry::KINDS.each_key do |kind|
        get new_bookkeeping_entry_path(kind: kind)
        assert_select "input[name='bookkeeping_entry[kind]'][value='#{kind}'][checked]"
        assert_select ".booking-entry-fields[disabled]", count: 0
      end
    end
  end

  test "year dropdown includes four previous years and extends to own historical records" do
    travel_to Time.zone.local(2026, 10, 17) do
      workspaces(:one).bookkeeping_entries.create!(kind: "income", description: "Fremde Historie", amount: 10, paid_on: "2000-01-01")
      get bookkeeping_entries_path
      assert_select "select#year option", count: 5
      assert_select "select#year option[selected][value='2026']"
      assert_select "select#year option[value='2022']"
      assert_select "select#year option[value='2000']", count: 0
      post bookkeeping_entries_path, params: { bookkeeping_entry: { kind: "income", description: "Alte Zahlung", amount: 10, paid_on: "2019-01-01" } }
      get bookkeeping_entries_path(year: 2019)
      assert_select "select#year option", count: 8
      assert_select "select#year option[selected][value='2019']"
      assert_select "select#year option[value='2020']"
      get bookkeeping_entries_path(year: 2018)
      assert_select "select#year option[selected][value='2018']"
    end
  end

  test "asset form is directly available without an intermediate guide" do
    assert_no_difference [ "Workspace.count", "BookkeepingEntry.count", "BusinessAsset.count" ] do
      get new_business_asset_path
      assert_response :success
      assert_select "[name='business_asset[asset_private_uses_attributes][0][business_percent]']"
      assert_select "a[href='/buchhaltung/geraete']", count: 0
      get "/buchhaltung/geraete"
      assert_redirected_to new_business_asset_path
    end
  end
end
