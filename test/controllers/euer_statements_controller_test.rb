require "test_helper"

class EuerStatementsControllerTest < ActionDispatch::IntegrationTest
  test "missing or special business data does not block bookings and preparation explains its limits" do
    patch euer_statement_url(year: 2026), params: { euer_statement: { details: { income_type: "1" } } }
    get prepare_euer_bookkeeping_entries_url(year: 2026)
    assert_response :success
    assert_select ".euer-preparation-check", /Noch zu ergänzen oder zu klären/
    assert_select ".euer-preparation-check", /Anlage LuF/
    assert_select "a[href='#{new_euer_adjustment_path(year: 2026, field_key: 'expense_livestock_reserve')}']"
    assert_difference "BookkeepingEntry.count", 1 do
      post bookkeeping_entries_url, params: { bookkeeping_entry: { kind: "expense", category: "expense_other", paid_on: "2026-10-12", amount: "100", description: "Kosten" } }
    end
    assert_response :redirect
    get edit_euer_statement_url(year: 2026)
    assert_select "details", count: 0
    assert_select ".euer-preparation-check", /keine Umsatzsteuerberechnung/
  end

  test "billing profile suggests missing details without overwriting saved annual data" do
    patch euer_statement_url(year: 2026), params: { euer_statement: { details: { income_type: "2" } } }
    statement = EuerStatement.last
    profile = statement.workspace.create_business_profile!(name: "Manuel Beck", tax_identifier: "12/345/67890")
    assert_no_difference "EuerStatement.count" do
      get edit_euer_statement_url(year: 2026)
    end
    assert_select "#euer_details_taxpayer_name[value='Manuel Beck']"
    assert_select "#euer_details_tax_number[value='12/345/67890']"
    assert_equal({ "income_type" => "2" }, statement.reload.details)
    patch euer_statement_url(year: 2026), params: { euer_statement: { details: { taxpayer_name: "Beck", first_name: "Manuel", tax_number: "", activity: "Softwareentwicklung" } } }
    profile.update!(name: "Anderer Rechnungsname", tax_identifier: "98/765/43210")
    get edit_euer_statement_url(year: 2026)
    assert_select "#euer_details_taxpayer_name[value='Beck']"
    assert_select "#euer_details_first_name[value='Manuel']"
    assert_select "#euer_details_tax_number" do |fields|
      assert fields.first["value"].blank?
    end
    assert_select "#euer_details_activity[value='Softwareentwicklung']"
    get edit_euer_statement_url(year: 2025)
    assert_select "#euer_details_taxpayer_name[value='Anderer Rechnungsname']"
    other = ActionDispatch::Integration::Session.new(Rails.application)
    other.get edit_euer_statement_url(year: 2026)
    assert_not_includes other.response.body, "Anderer Rechnungsname"
  end

  test "VAT identifiers never populate the EÜR tax number" do
    patch euer_statement_url(year: 2026), params: { euer_statement: { details: { income_type: "2" } } }
    EuerStatement.last.workspace.create_business_profile!(name: "Mein Betrieb", tax_identifier: "DE123456789")
    get edit_euer_statement_url(year: 2026)
    assert_select "#euer_details_taxpayer_name[value='Mein Betrieb']"
    assert_select "#euer_details_tax_number" do |fields|
      assert fields.first["value"].blank?
    end
  end

  test "full form and details are scoped saved exported and complete" do
    get edit_euer_statement_url(year: 2026)
    assert_response :success
    assert_select "details", count: 0
    assert_select "tr[data-euer-line='13']", /davon nicht steuerbare Umsätze/
    assert_select "tr[data-euer-line='108']", /Einlagen/
    assert_select "tr[data-euer-line='98']", /Automatisch berechnet/
    assert_no_difference "EuerStatement.count" do
      get edit_euer_statement_url(year: 2025)
    end
    patch euer_statement_url(year: 2026), params: { euer_statement: { details: { taxpayer_name: "Mein Betrieb", income_type: "2" } } }
    assert_response :redirect
    record = EuerStatement.last
    get edit_euer_statement_url(year: 2026)
    assert_select "input[value='Mein Betrieb']"
    get bookkeeping_entries_url(year: 2026, format: :csv)
    assert_includes response.body, "Mein Betrieb"
    other = ActionDispatch::Integration::Session.new(Rails.application)
    other.get edit_euer_statement_url(year: 2026)
    assert_not_includes other.response.body, "Mein Betrieb"
    other.patch euer_statement_url(year: 2026), params: { euer_statement: { details: { taxpayer_name: "Anderer Betrieb" } } }
    assert_not_equal record.workspace_id, EuerStatement.last.workspace_id
    assert_equal "Mein Betrieb", record.reload.details["taxpayer_name"]
    get edit_euer_statement_url(year: 2024)
    assert_response :not_found
  end

  test "import retains supplementary fields general details and safe preview totals" do
    post preview_bookkeeping_imports_url, params: { bookkeeping_import: {
      year: 2025, covered_through: "2025-12-31", source: "sevdesk", amounts: { income_small: "1000", income_small_details: "300", vat_collected: "19" },
      details: { taxpayer_name: "Übernommener Betrieb", activity: "Beratung" }
    } }
    assert_response :success
    assert_select "dd", "1.019,00 €"
    assert_select "tr[data-euer-line='13']", /300,00 €/
    assert_select "tr[data-euer-line='1']", /Übernommener Betrieb/
    token = Nokogiri::HTML(response.body).at_css("input[name=token]")["value"]
    post bookkeeping_imports_url, params: { token: token, confirmed: "1" }
    assert_response :redirect
    assert_equal "Übernommener Betrieb", BookkeepingImport.last.details["taxpayer_name"]
    get edit_euer_statement_url(year: 2025)
    assert_select "input[value='Übernommener Betrieb']"
    get export_url
    names = []
    Zip::InputStream.open(StringIO.new(response.body)) do |zip|
      while (item = zip.get_next_entry)
        names << item.name
      end
    end
    assert_includes names, "euer-uebernahmen-betriebsangaben.json"
  end
end
