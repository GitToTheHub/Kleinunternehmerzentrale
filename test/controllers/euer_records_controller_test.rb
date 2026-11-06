require "test_helper"

class EuerRecordsControllerTest < ActionDispatch::IntegrationTest
  def asset_params
    { name: "Computer", acquired_on: "2026-10-12", paid_on: "2026-10-12", cost: "1200,00", useful_life: 3 }
  end

  test "guest can manage assets schedules and tax adjustments and export all tax data" do
    assert_no_difference "Workspace.count" do
      get business_assets_url
      assert_response :success
      get new_business_asset_url
      assert_response :success
      get new_euer_adjustment_url(year: 2025)
      assert_response :success
      assert_select "select[name='euer_adjustment[year]'] option[selected]", "2025"
    end
    post business_assets_url, params: { business_asset: asset_params.merge(workspace_id: workspaces(:one).id,
      asset_depreciations_attributes: { "0" => { year: "", amount: "", special_amount: "0.0", reason: "" } }) }
    assert_redirected_to business_assets_url
    asset = BusinessAsset.order(:id).last
    assert_not_equal workspaces(:one), asset.workspace
    assert_empty asset.asset_depreciations
    follow_redirect!
    assert_select "td", /Computer/
    assert_select ".guest-notice"
    get edit_business_asset_url(asset)
    assert_response :success
    patch business_asset_url(asset), params: { business_asset: {
      asset_depreciations_attributes: { "0" => { year: 2026, amount: "200,00", special_amount: 0, reason: "Abweichende geprüfte AfA" } }
    } }
    assert_response :redirect
    assert_equal 200, asset.reload.schedule(2026)[:ordinary]
    post euer_adjustments_url, params: { euer_adjustment: { year: 2026, field_key: "expense_home_days", amount: "60,00", description: "Zehn Arbeitstage", workspace_id: workspaces(:one).id } }
    adjustment = EuerAdjustment.order(:id).last
    assert_equal asset.workspace, adjustment.workspace
    follow_redirect!
    assert_response :success
    assert_select "dd strong", "-260,00 €"
    assert_select "a[href='#{edit_euer_adjustment_path(adjustment)}']"
    get edit_euer_adjustment_url(adjustment)
    assert_response :success
    patch euer_adjustment_url(adjustment), params: { euer_adjustment: { amount: "66,00" } }
    assert_equal 66, adjustment.reload.amount
    get bookkeeping_entries_url(year: 2026, format: :csv)
    assert_includes response.body, "AVEÜR-Gruppe"
    assert_includes response.body, "Computer"
    get export_url
    entries = {}
    Zip::InputStream.open(StringIO.new(response.body)) do |zip|
      while (item = zip.get_next_entry)
        entries[item.name] = zip.read.force_encoding("UTF-8")
      end
    end
    assert_includes entries.keys, "anlagegueter.csv"
    assert_includes entries.keys, "abschreibungen.csv"
    assert_includes entries.keys, "euer-ergaenzungen.csv"
    assert_includes entries["abschreibungen.csv"], "Abweichende geprüfte AfA"
    delete euer_adjustment_url(adjustment)
    assert_response :see_other
    assert_not EuerAdjustment.exists?(adjustment.id)
    delete business_asset_url(asset)
    assert_response :see_other
    assert_not BusinessAsset.exists?(asset.id)
    assert_equal 0, AssetDepreciation.where(business_asset_id: asset.id).count
  end

  test "foreign assets adjustments and nested schedule IDs cannot be accessed" do
    other = workspaces(:one).business_assets.create!(asset_params)
    schedule = other.asset_depreciations.create!(year: 2026, amount: 100, reason: "Anderer Bereich")
    adjustment = workspaces(:one).euer_adjustments.create!(year: 2026, field_key: "expense_home_days", amount: 6, description: "Privat")
    [ edit_business_asset_url(other), edit_euer_adjustment_url(adjustment) ].each do |url|
      get url
      assert_response :not_found
    end
    patch business_asset_url(other), params: { business_asset: { cost: "1" } }
    assert_response :not_found
    delete business_asset_url(other)
    assert_response :not_found
    patch euer_adjustment_url(adjustment), params: { euer_adjustment: { amount: "1" } }
    assert_response :not_found
    delete euer_adjustment_url(adjustment)
    assert_response :not_found
    post business_assets_url, params: { business_asset: asset_params }
    mine = BusinessAsset.order(:id).last
    patch business_asset_url(mine), params: { business_asset: { asset_depreciations_attributes: { "0" => { id: schedule.id, amount: 1 } } } }
    assert_response :not_found
    assert_equal 100, schedule.reload.amount
    get bookkeeping_entries_url(year: 2026, format: :csv)
    assert_not_includes response.body, "Anderer Bereich"
  end

  test "invalid asset or adjustment redisplays the form without saving" do
    assert_no_difference "BusinessAsset.count" do
      post business_assets_url, params: { business_asset: asset_params.merge(cost: "12,345") }
    end
    assert_response :unprocessable_entity
    assert_no_difference "EuerAdjustment.count" do
      post euer_adjustments_url, params: { euer_adjustment: { year: 2027, field_key: "expense_home_days", amount: "12,345", description: "Ungültig" } }
    end
    assert_response :unprocessable_entity
  end

  test "erasing workspace removes assets schedules and adjustments" do
    post business_assets_url, params: { business_asset: asset_params }
    item = BusinessAsset.order(:id).last
    item.asset_depreciations.create!(year: 2026, amount: 100, reason: "AfA")
    item.workspace.euer_adjustments.create!(year: 2026, field_key: "expense_home_days", amount: 6, description: "Tag")
    delete account_url
    assert_not Workspace.exists?(item.workspace_id)
    assert_not BusinessAsset.exists?(item.id)
    assert_equal 0, AssetDepreciation.where(business_asset_id: item.id).count
    assert_equal 0, EuerAdjustment.where(workspace_id: item.workspace_id).count
  end
  test "asset form retains small business tax treatment while EÜR adjustments support every tax field" do
    get new_business_asset_url
    assert_select "input[name='business_asset[input_vat]']", count: 0
    assert_select "input[name='business_asset[withdrawal_vat]']", count: 0
    assert_select "input[name='business_asset[gwg_net_value]']", count: 1
    post business_assets_url, params: { business_asset: asset_params.merge(input_vat: "228", withdrawal_vat: "19") }
    assert_response :redirect
    assert_equal 0, BusinessAsset.order(:id).last.input_vat
    assert_equal 0, BusinessAsset.order(:id).last.withdrawal_vat
    get new_euer_adjustment_url(year: 2026)
    EuerFields::REGULAR_TAX_KEYS.each do |key|
      get new_euer_adjustment_url(year: 2026)
      assert_select "select[name='euer_adjustment[field_key]'] option[value='#{key}']", count: 1
      assert_difference "EuerAdjustment.count" do
        post euer_adjustments_url, params: { euer_adjustment: { year: 2026, field_key: key, amount: 19, description: "Regelbesteuerung" } }
      end
      assert_response :redirect
    end
  end
  test "annual asset usage is saved edited exported and erased in its own workspace" do
    post business_assets_url, params: { business_asset: asset_params.merge(
      asset_private_uses_attributes: { "0" => { year: 2026, business_percent: "60,5", basis: "Aufzeichnungen", calculation_mode: "depreciation" } }) }
    assert_response :redirect
    asset = BusinessAsset.order(:id).last
    usage = asset.asset_private_uses.sole
    assert_equal BigDecimal("39.5"), usage.amount
    get edit_business_asset_url(asset)
    assert_response :success
    assert_select "textarea", "Aufzeichnungen"
    patch business_asset_url(asset), params: { business_asset: { asset_private_uses_attributes: { "0" => { id: usage.id, business_percent: 80 } } } }
    assert_response :redirect
    assert_equal 20, usage.reload.amount
    get bookkeeping_entries_url(year: 2026, format: :csv)
    assert_includes response.body, "Private Nutzung Anlagegut"
    assert_includes response.body, "Aufzeichnungen"
    other = Workspace.create!.business_assets.create!(asset_params)
    foreign_usage = other.asset_private_uses.create!(year: 2026, business_percent: 50, basis: "Fremder Bereich")
    patch business_asset_url(asset), params: { business_asset: { asset_private_uses_attributes: { "0" => { id: foreign_usage.id, business_percent: 99 } } } }
    assert_response :not_found
    assert_equal 50, foreign_usage.reload.business_percent
    delete account_url
    assert_not AssetPrivateUse.exists?(usage.id)
    assert AssetPrivateUse.exists?(foreign_usage.id)
  end
end
