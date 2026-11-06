require "test_helper"

class EuerDaycareAllowanceTest < ActiveSupport::TestCase
  def regular(label, start_month, end_month, hours)
    { "label" => label, "start_month" => start_month, "end_month" => end_month, "kind" => "regular", "weekly_hours" => hours }
  end

  def reserve(start_month, end_month, days, hours)
    { "label" => "Freihalteplatz", "start_month" => start_month, "end_month" => end_month, "kind" => "reserved", "occupied_days" => days, "daily_hours" => hours }
  end

  test "official BMF example is reproduced including capped hours and occupied reserve days" do
    rows = [ regular("Kind 1", 1, 12, 40), regular("Kind 2", 2, 11, 20), regular("Kind 3", 8, 12, 45),
      regular("Kind 4", 1, 12, 18), reserve(1, 10, 0, 0), reserve(11, 11, 12, 6), reserve(12, 12, 4, 8) ]
    [ 2025, 2026 ].each do |year|
      calculation = EuerDaycareAllowance.new(rows, year)
      assert_empty calculation.errors
      assert_equal 11_780, calculation.amount
    end
  end

  test "overlapping children months malformed hours and invalid reserve days are rejected" do
    [ [ regular("Kind A", 1, 12, "20,50"), regular("kind a", 8, 12, 20) ],
      [ regular("Kind A", 2, 1, 20) ], [ regular("Kind A", 1, 12, "20abc") ],
      [ reserve(1, 12, 21, 8) ], [ reserve(1, 12, 5, 0) ] ].each do |rows|
      calculation = EuerDaycareAllowance.new(rows, 2026)
      assert calculation.errors.any?
      assert_equal 0, calculation.amount
    end
    assert EuerDaycareAllowance.new([], 2026).errors.any?
    assert EuerDaycareAllowance.new([ regular("A", 1, 12, 40) ], 2027).errors.any?
  end

  test "daycare deduction is limited to taxable business revenue and replaces actual costs" do
    workspace = Workspace.create!
    statement = workspace.euer_statements.create!(year: 2026, details: { "legal_form" => "Einzelunternehmen", "income_type" => "3" })
    workspace.bookkeeping_entries.create!(kind: "income", category: "income_small", paid_on: "2026-06-01", amount: 3000, description: "Betreuung und Erstattung")
    workspace.bookkeeping_entries.create!(kind: "expense", category: "expense_supplies", paid_on: "2026-06-01", amount: 100, description: "Material")
    workspace.euer_adjustments.create!(year: 2026, field_key: "tax_exempt_other", amount: 500, description: "Steuerfreie Versicherungsbeitragserstattung")
    selected = workspace.euer_expense_policies.new(year: 2026, deduction_method: "daycare", eligibility_confirmed: true,
      daycare_eligibility_confirmed: true, daycare_rows: { "0" => regular("A", 1, 12, 40) })
    assert selected.save, selected.errors.full_messages.to_sentence
    report = BookkeepingReport.new(workspace.bookkeeping_entries, 2026, adjustments: workspace.euer_adjustments, statement: statement, expense_policy: selected)
    assert_equal 2500, report.expenses
    assert_equal 0, report.surplus
    assert_equal 0, report.field_totals["expense_supplies"]
    assert_equal 500, report.field_totals["tax_exempt_other"]
    selected.daycare_eligibility_confirmed = false
    assert_not selected.valid?
  end
end
