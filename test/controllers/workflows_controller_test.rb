require "test_helper"

class WorkflowsControllerTest < ActionDispatch::IntegrationTest
  test "billing preferences are saved independently while all features are available" do
    assert_no_difference "Workspace.count" do
      get edit_workflow_path
      assert_redirected_to new_invoice_path(anchor: "billing-units")
      get new_invoice_path
      assert_select "nav a", text: "Einstellungen", count: 0
      assert_select "#billing-units[popover]"
      assert_select "#billing-units input[type='checkbox'][checked]", count: InvoiceLine::UNIT_CODES.size
      assert_select "select#invoice_currency"
      assert_select "select#invoice_buyer_country"
      assert_select "select#invoice_invoice_lines_attributes_0_unit_code option:not([value=''])", count: InvoiceLine::UNIT_CODES.size
      get bookkeeping_entries_path
      assert_select "a[href='#{business_assets_path}']"
      assert_select "h2", text: /Anlageverzeichnis und Abschreibungen/
      assert_select "h2", text: "Steuerliche Ergänzungen"
      get new_bookkeeping_entry_path
      assert_select "[data-controller='booking-help']", count: 0
      get new_business_asset_path
      assert_select "input[name='business_asset[asset_private_uses_attributes][0][business_percent]']"
    end
    patch workflow_path, params: { workflow: { units: %w[LS], assets: "0", international: "0" } }, as: :json
    assert_response :success
    assert_equal({ "units" => [ "LS" ] }, response.parsed_body)
    assert_equal({ "units" => [ "LS" ] }, Workspace.order(:id).last.workflow)
    assert_equal InvoiceLine::UNIT_CODES.keys.sort, workspaces(:one).workflow["units"].sort
    get new_invoice_path
    assert_select "select#invoice_invoice_lines_attributes_0_unit_code option:not([value=''])", count: 1
    assert_select "select#invoice_currency"
  end

  test "invalid unit selection does not create a workspace" do
    [ [], [ "BAD" ] ].each do |units|
      assert_no_difference "Workspace.count" do
        patch workflow_path, params: { workflow: { units: units } }, as: :json
        assert_response :unprocessable_entity
      end
    end
  end

  test "reopening an old draft does not add its disabled unit to the selection" do
    patch workflow_path, params: { workflow: { units: %w[MON LS] } }, as: :json
    workspace = Workspace.order(:id).last
    draft = workspace.invoice_drafts.create!(data: {
      "invoice_lines_attributes" => { "0" => { "description" => "Alte Stundenposition", "quantity" => "3", "unit_price" => "85", "unit_code" => "HUR", "tax_rate" => "0" } }
    })
    get edit_draft_invoices_path(draft_id: draft.id)
    assert_response :success
    assert_select "select[name$='[unit_code]']" do
      assert_select "option[value='HUR']", count: 0
      assert_select "option[value='MON'][selected]"
    end
    assert_equal "HUR", draft.reload.data.dig("invoice_lines_attributes", "0", "unit_code")
  end

  test "old hidden feature settings no longer change visibility" do
    post bookkeeping_entries_path, params: { bookkeeping_entry: { kind: "income", paid_on: "2026-10-01", amount: 50, description: "Honorar" } }
    workspace = BookkeepingEntry.order(:id).last.workspace
    workspace.update!(workflow_settings: { "assets" => false, "international" => false, "advanced" => false, "units" => %w[HUR] })
    get bookkeeping_entries_path(year: 2026)
    assert_select "td", text: "Honorar"
    assert_select "a[href='#{business_assets_path}']"
    get new_invoice_path
    assert_select "select#invoice_currency"
    assert_select "input[name='workflow[activity_areas][]']", count: 0
  end
end
