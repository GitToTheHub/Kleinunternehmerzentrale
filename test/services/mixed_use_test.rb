require "test_helper"

class MixedUseTest < ActiveSupport::TestCase
  setup { @workspace = Workspace.create! }

  def expense(**attributes)
    @workspace.bookkeeping_entries.create!({ kind: "expense", category: "expense_phone", description: "Mobilfunk",
      paid_on: "2026-10-01", amount: 20, business_percent: 60, usage_notes: "Telefonate Januar bis März ausgewertet" }.merge(attributes))
  end

  def report
    BookkeepingReport.new(@workspace.bookkeeping_entries, 2026)
  end

  test "private payment contributes only the business share and refund reverses it" do
    original = expense(payment_account: "private")
    assert_equal 12, report.expenses
    assert_equal 12, report.deposits
    assert_equal 12, report.automatic_money_movements("deposit").sole[:amount]
    assert_equal 0, report.withdrawals
    original.refunds.create!(original.refund_attributes.merge(workspace: @workspace, paid_on: "2026-10-02", amount: 10, description: "Erstattung", payment_account: "private"))
    assert_equal 6, report.expenses
    assert_equal 6, report.deposits
    assert_equal 0, report.withdrawals
    assert_not original.update(business_percent: 80)
  end

  test "business payment records the private portion as withdrawal" do
    expense(payment_account: "business")
    assert_equal 12, report.expenses
    assert_equal 0, report.deposits
    assert_equal 8, report.withdrawals
    assert_equal 8, report.automatic_money_movements("withdrawal").sole[:amount]
  end

  test "business use and statutory deduction are distinct" do
    expense(category: "expense_meals", amount: 100, business_percent: 80, payment_account: "private")
    assert_equal 56, report.expenses
    assert_equal 24, report.field_totals["meals_disallowed"]
    assert_equal 80, report.deposits
  end

  test "share requires evidence valid bounds and expense kind" do
    entry = expense
    assert_not entry.update(business_percent: 0)
    assert_not entry.update(business_percent: 101)
    assert_not entry.update(business_percent: 60, usage_notes: "")
    assert_not entry.update(kind: "income", category: "income_small", business_percent: 60, usage_notes: "Test")
  end
  test "asset usage is documented without silently changing depreciation" do
    asset = @workspace.business_assets.new(name: "Mac", acquired_on: "2026-01-01", paid_on: "2026-01-01",
      cost: 1200, useful_life: 3, business_use_percent: "60,5", usage_basis: "Nutzungsaufzeichnung Januar bis März")
    assert asset.save
    assert_equal BigDecimal("60.5"), asset.business_use_percent
    assert_equal 400, asset.schedule(2026)[:ordinary]
    result = BookkeepingReport.new(@workspace.bookkeeping_entries, 2026, assets: @workspace.business_assets)
    assert result.warnings.any? { |warning| warning.include?("Nutzungsanteil nur dokumentiert") }
    assert_not asset.update(usage_basis: "")
  end
end
