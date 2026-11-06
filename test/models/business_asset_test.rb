require "test_helper"

class BusinessAssetTest < ActiveSupport::TestCase
  def asset(**attributes)
    Workspace.create!.business_assets.new({ name: "Computer", acquired_on: Date.new(2026, 10, 12), paid_on: Date.new(2026, 10, 12), cost: "1.200,00", useful_life: 3 }.merge(attributes))
  end

  test "linear depreciation includes acquisition month and closes exactly to zero" do
    item = asset
    assert item.valid?, item.errors.full_messages.to_sentence
    assert_equal 0, item.schedule(2025)[:closing]
    assert_equal 100, item.schedule(2026)[:ordinary]
    assert_equal 1100, item.schedule(2026)[:closing]
    assert_equal 1100, item.schedule(2027)[:opening]
    assert_equal 400, item.schedule(2027)[:ordinary]
    assert_equal 300, item.schedule(2029)[:ordinary]
    assert_equal 0, item.schedule(2029)[:closing]
    assert_equal 0, item.schedule(2030)[:ordinary]
    item.cost = "1000,01"
    assert_equal item.cost, (2026..2029).sum { |year| item.schedule(year)[:ordinary] }
  end

  test "private asset contributions do not deduct full cost immediately" do
    item = asset(origin: "contribution", paid_on: nil)
    item.save!
    report = BookkeepingReport.new(item.workspace.bookkeeping_entries, 2026, assets: item.workspace.business_assets)
    assert_equal 1200, report.deposits
    assert_equal 100, report.expenses
    assert_equal 0, report.income
    assert_equal(-100, report.surplus)
  end

  test "GWG threshold uses the net value even for a small business gross deduction" do
    item = asset(cost: "952,00", depreciation_method: "gwg", gwg_net_value: "800,00")
    assert item.valid?, item.errors.full_messages.to_sentence
    assert_equal 952, item.schedule(2026)[:ordinary]
    assert_equal 0, item.schedule(2027)[:ordinary]
    item.gwg_net_value = "800,01"
    assert_not item.valid?
    item.gwg_net_value = "800,00"
    item.category = "intangible"
    assert_not item.valid?
  end

  test "asset withdrawal combines income equity and residual expense without duplication" do
    item = asset(disposed_on: "2027-04-20", disposal_kind: "withdrawal", withdrawal_value: 800, withdrawal_vat: 152)
    item.save!
    report = BookkeepingReport.new(item.workspace.bookkeeping_entries, 2027, assets: item.workspace.business_assets)
    assert_equal BigDecimal("133.33"), item.schedule(2027)[:ordinary]
    assert_equal BigDecimal("966.67"), item.schedule(2027)[:residual]
    assert_equal 1100, report.expenses
    assert_equal 952, report.income
    assert_equal 952, report.withdrawals
    assert_equal 0, item.schedule(2027)[:closing]
    assert_equal 0, item.schedule(2028)[:ordinary]
    assert_equal 0, item.schedule(2028)[:residual]
  end

  test "manual annual and special deductions preserve book values and reject excess" do
    item = asset(depreciation_method: "manual", acquired_on: "2026-01-01")
    item.asset_depreciations.build(year: 2026, amount: 400, special_amount: 200, reason: "Geprüfte Sonder-AfA")
    item.asset_depreciations.build(year: 2027, amount: 300, special_amount: 0, reason: "Geprüfte Folge-AfA")
    assert item.valid?, item.errors.full_messages.to_sentence
    assert_equal 600, item.schedule(2026)[:closing]
    assert_equal 600, item.schedule(2027)[:opening]
    assert_equal 300, item.schedule(2027)[:closing]
    item.asset_depreciations.last.amount = 601
    assert_not item.valid?
    item.asset_depreciations.last.amount = 300
    item.depreciation_method = "linear"
    assert_not item.valid?, "special deductions need an explicit manual follow-up schedule"
  end

  test "blank schedule rows are ignored and duplicate years are rejected before DB writes" do
    item = asset(asset_depreciations_attributes: { "0" => { year: "", amount: "", special_amount: "0.0", reason: "" } })
    item.save!
    assert_empty item.asset_depreciations
    item.asset_depreciations.build(year: 2026, amount: 100, special_amount: 0, reason: "Erster")
    item.asset_depreciations.build(year: 2026, amount: 100, special_amount: 0, reason: "Zweiter")
    assert_not item.valid?
  end

  test "non depreciable sale recognizes residual only when proceeds arrive" do
    item = asset(category: "land", depreciation_method: "none", disposed_on: "2027-12-01", disposal_kind: "sale", disposal_recognized_on: "2028-01-05")
    assert item.valid?, item.errors.full_messages.to_sentence
    assert_equal 1200, item.schedule(2027)[:closing]
    assert_equal 0, item.schedule(2027)[:residual]
    assert_equal 1200, item.schedule(2028)[:residual]
    assert_equal 0, item.schedule(2028)[:closing]
    item.disposal_recognized_on = nil
    assert_not item.valid?
  end

  test "amount and disposal validation never silently round or misclassify" do
    item = asset(cost: "1200,123")
    assert_not item.valid?
    item.cost = 1200
    item.disposed_on = "2025-01-01"
    item.disposal_kind = "withdrawal"
    assert_not item.valid?
    item.disposed_on = "2027-01-01"
    assert_not item.valid?, "withdrawal value must be explicit, even when zero"
    item.withdrawal_value = 0
    assert item.valid?, item.errors.full_messages.to_sentence
  end
end
