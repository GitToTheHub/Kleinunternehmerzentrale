require "test_helper"

class EuerTaxRulesTest < ActiveSupport::TestCase
  test "form support and checked calculation values require separate yearly registration" do
    [ 2025, 2026 ].each do |year|
      assert EuerTaxRules.checked?(year)
      assert_nil EuerTaxRules.warning(year)
      assert_equal 70, EuerTaxRules.for(year).meals_percent
      assert_equal 800, EuerTaxRules.for(year).gwg_limit
      assert_equal 2050, EuerTaxRules.for(year).interest_threshold
    end
    [ 2022, 2027 ].each do |year|
      assert_not EuerTaxRules.checked?(year)
      assert_includes EuerTaxRules.warning(year), year.to_s
      assert_equal 70, EuerTaxRules.for(year).meals_percent
    end
  end

  test "unknown years retain calculations but disclose their provisional status in the report" do
    workspace = Workspace.create!
    entry = workspace.bookkeeping_entries.create!(kind: "expense", category: "expense_meals",
      paid_on: "2022-05-01", description: "Bewirtung", amount: 100)
    report = BookkeepingReport.new(workspace.bookkeeping_entries, 2022)
    assert_equal 70, entry.deductible_amount
    assert_includes report.warnings, EuerTaxRules.warning(2022)
    assert_not_includes BookkeepingReport.new(workspace.bookkeeping_entries, 2026).warnings, EuerTaxRules.warning(2022)
    entry.deductible_percent = 50
    assert_equal 50, entry.deductible_amount
  end
end
