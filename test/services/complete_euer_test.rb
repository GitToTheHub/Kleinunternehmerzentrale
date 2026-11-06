require "test_helper"

class CompleteEuerTest < ActiveSupport::TestCase
  setup { @workspace = Workspace.create! }

  test "main form has every official line for both supported years" do
    { 2025 => 107, 2026 => 108 }.each do |year, last|
      assert_equal (1..last).to_a, EuerForm.rows(year).map(&:line).uniq.sort
      assert_equal 13, EuerFields.line("income_small_details", year)
      assert_equal "119", EuerFields::DEFINITIONS.fetch("income_small_details").number
      assert_equal :info, EuerFields::DEFINITIONS.fetch("income_small_details").effect
    end
    assert_nil EuerFields.line("expense_livestock_reserve", 2025)
    assert_equal 27, EuerFields.line("expense_livestock_reserve", 2026)
    assert_equal 27, EuerFields.line("expense_goods", 2025)
    assert_equal 29, EuerFields.line("expense_goods", 2026)
  end

  test "reserve transfers and informational totals contribute exactly once" do
    imported = @workspace.bookkeeping_imports.create!(year: 2025, covered_through: "2025-12-31", source: "Geprüfte EÜR", amounts: {
      "income_small" => "1000", "income_small_details" => "100", "income_agriculture" => "50",
      "reserve_release" => "10", "allocation_release" => "5", "expense_goods" => "100",
      "expense_profession_allowance" => "20", "reserve_create" => "40", "reserve_transfer" => "10",
      "allocation_create" => "5", "expense_property" => "80", "property_repairs_details" => "20",
      "investment_total" => "900", "partial_income_total" => "500", "investment_correction" => "10",
      "partial_income_correction" => "20", "interest_addback" => "5"
    })
    result = BookkeepingReport.new(@workspace.bookkeeping_entries, 2025, imports: @workspace.bookkeeping_imports)
    assert_equal 1065, result.income
    assert_equal 255, result.expenses
    assert_equal 845, result.surplus
    assert_equal imported.surplus, result.surplus
    assert_equal 15, EuerForm.amount("reserve_income_total", result)
    assert_equal 55, EuerForm.amount("reserve_expense_total", result)
    assert_equal 120, EuerForm.amount("first_expense_carry", result)
    assert_equal 255, EuerForm.amount("expense_carry", result)
    assert_equal 810, EuerForm.amount("corrected_profit", result)
    assert_equal 840, EuerForm.amount("profit_before_interest", result)
    assert_equal 845, EuerForm.amount("profit_total", result)
    assert_equal 815, EuerForm.amount("partnership_profit", result)
    assert_includes result.csv, "Vollständige Anlage EÜR"
    assert_includes result.csv, "davon nicht steuerbare Umsätze"
  end

  test "year specific and subset fields are validated for imports and adjustments" do
    item = @workspace.bookkeeping_imports.new(year: 2025, covered_through: "2025-12-31", source: "Test", amounts: { "income_small" => "100", "income_small_details" => "101" })
    assert_not item.valid?
    item.amounts["income_small_details"] = "100"
    assert item.valid?, item.errors.full_messages.to_sentence
    item.amounts["expense_livestock_reserve"] = "20"
    assert_not item.valid?
    item.year = 2026
    item.covered_through = "2026-10-01"
    assert item.valid?, item.errors.full_messages.to_sentence
    record = @workspace.euer_adjustments.new(year: 2025, field_key: "expense_livestock_reserve", amount: 20, description: "Begründung")
    assert_not record.valid?
    record.year = 2026
    assert record.valid?
    assert_equal({ "income_small_details" => "100.0", "vat_collected" => "19.0" }, EuerTotalsImport.manual({ "income_small_details" => "100", "vat_collected" => "19" }))
  end

  test "2026 expense carry includes new agricultural reserve but not goods until line 29" do
    imported = BookkeepingImport.new(year: 2026, amounts: { "expense_forestry" => "20", "expense_vineyard" => "3", "expense_livestock_reserve" => "4", "expense_goods" => "100" })
    report = BookkeepingReport.new(BookkeepingEntry.none, 2026, imports: [ imported ])
    assert_equal 27, EuerForm.amount("first_expense_carry", report)
    assert_equal 127, EuerForm.amount("expense_carry", report)
    assert_equal 127, report.expenses
    assert_equal(-127, report.surplus)
  end

  test "details validate preserve meaning and delete with workspace" do
    record = @workspace.euer_statements.create!(year: 2026, details: { "taxpayer_name" => "Testbetrieb", "income_type" => "2", "property_disposal" => "2" })
    report = BookkeepingReport.new(@workspace.bookkeeping_entries, 2026, statement: record)
    assert_equal "Gewerbebetrieb", report.detail_value("income_type")
    assert_equal "Nein", report.detail_value("property_disposal")
    assert_includes report.csv, "Testbetrieb"
    assert_not record.update(details: { "income_type" => "99" })
    assert_not record.update(details: { "period_start" => "2026-01-01" })
    assert_not record.update(details: { "period_start" => [], "period_end" => "2026-01-01" })
    @workspace.erase!
    assert_not EuerStatement.exists?(record.id)
  end
end
