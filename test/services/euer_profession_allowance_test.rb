require "test_helper"

class EuerProfessionAllowanceTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!
    @statement = @workspace.euer_statements.create!(year: 2026, details: { "legal_form" => "Einzelunternehmen", "income_type" => "3" })
  end

  def income(amount, year: 2026)
    @workspace.bookkeeping_entries.create!(kind: "income", category: "income_small", paid_on: "#{year}-06-01", amount: amount, description: "Honorar")
  end

  def report(policy = nil, year: 2026)
    BookkeepingReport.new(@workspace.bookkeeping_entries, year, assets: @workspace.business_assets,
      adjustments: @workspace.euer_adjustments, imports: @workspace.bookkeeping_imports,
      statement: @statement, expense_policy: policy)
  end

  def policy(method = "writer_main", year: 2026)
    @workspace.euer_expense_policies.new(year: year, deduction_method: method, eligibility_confirmed: true)
  end

  test "allowance replaces expenses and AfA without changing payments or book values" do
    income(20_000)
    expense = @workspace.bookkeeping_entries.create!(kind: "expense", category: "expense_other", paid_on: "2026-06-01", amount: 1000, description: "Kosten", payment_account: "private")
    asset = @workspace.business_assets.create!(name: "Arbeitsmittel", acquired_on: "2026-01-01", paid_on: "2026-01-01", cost: 1200, useful_life: 3)
    selected = policy
    assert selected.save, selected.errors.full_messages.to_sentence
    result = report(selected)
    assert_equal 1400, report.expenses
    assert_equal 3600, result.expenses
    assert_equal 16_400, result.surplus
    assert_equal 3600, result.field_totals["expense_profession_allowance"]
    assert_equal 0, result.field_totals["expense_other"]
    assert_equal 0, result.field_totals["afa_movable"]
    assert_equal 1000, result.deposits
    assert_equal 1000, expense.reload.amount
    assert_equal 800, asset.reload.schedule(2026)[:closing]
    assert_includes result.csv, "Betriebsausgabenpauschale ersetzt die tatsächlichen Ausgaben"
    selected.update!(deduction_method: "actual")
    assert_equal 1400, report(selected).expenses
  end

  test "annual revenue changes recalculate percentages while the side activity cap is shared" do
    income("1000,01")
    selected = policy
    selected.save!
    assert_equal BigDecimal("300.00"), report(selected).expenses
    income(1000)
    assert_equal BigDecimal("600.00"), report(selected).expenses
    selected.update!(deduction_method: "eligible_side")
    assert_equal BigDecimal("500.00"), report(selected).expenses
    income(5000)
    assert_equal 900, report(selected).expenses
    assert_not @workspace.euer_expense_policies.new(year: 2026, deduction_method: "eligible_side", eligibility_confirmed: true).valid?
  end

  test "unconfirmed mixed and special contexts are rejected instead of guessing" do
    income(2000)
    selected = policy
    selected.eligibility_confirmed = false
    assert_not selected.valid?
    selected.eligibility_confirmed = true
    @statement.update!(details: { "income_type" => "1", "legal_form" => "Einzelunternehmen" })
    assert_not selected.valid?
    @statement.update!(details: { "income_type" => "3", "legal_form" => "GmbH" })
    assert_not selected.valid?
    @statement.update!(details: { "income_type" => "3", "legal_form" => "Einzelunternehmen", "period_start" => "2026-07-01", "period_end" => "2027-06-30" })
    assert_not selected.valid?
    assert_not policy(year: 2027).valid?
  end

  test "later special entries visibly suspend the automatic election and retain actual amounts" do
    income(2000)
    selected = policy
    selected.save!
    assert_equal 600, report(selected).expenses
    @workspace.bookkeeping_entries.create!(kind: "expense", category: "expense_other", paid_on: "2026-06-01", amount: 100, description: "Kosten")
    @workspace.euer_adjustments.create!(year: 2026, field_key: "method_change", amount: 50, description: "Übergang")
    result = report(selected)
    assert_equal 100, result.expenses
    assert_equal 1950, result.surplus
    assert_includes result.warnings.join, "wird nicht angewendet"
    assert_includes result.csv, "vorläufig die tatsächlichen Ausgaben"
    selected.update!(deduction_method: "actual")
    assert_not_includes report(selected).warnings.join, "wird nicht angewendet"
  end

  test "manual allowance values are never doubled and different years do not inherit elections" do
    income(2000)
    @workspace.euer_adjustments.create!(year: 2026, field_key: "expense_profession_allowance", amount: 600, description: "Bereits ermittelt")
    selected = policy
    assert_not selected.valid?
    assert_includes selected.errors.full_messages.join, "Doppelung"
    assert_not report(selected, year: 2025).allowance.applicable?
  end
end
