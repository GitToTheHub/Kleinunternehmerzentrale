require "test_helper"

class EuerHomeOfficeAllowanceTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!
    @statement = @workspace.euer_statements.create!(year: 2026, details: { "legal_form" => "Einzelunternehmen", "income_type" => "2" })
  end

  def policy(**attributes)
    @workspace.euer_expense_policies.new({ year: 2026, home_office_method: "days", home_days: 20,
      home_basis: "Datierte Arbeitstageliste", home_eligibility_confirmed: true }.merge(attributes))
  end

  def report(selected)
    BookkeepingReport.new(@workspace.bookkeeping_entries, 2026, adjustments: @workspace.euer_adjustments,
      imports: @workspace.bookkeeping_imports, statement: @statement, expense_policy: selected)
  end

  test "documented days count once up to the annual maximum without inventing a payment" do
    selected = policy
    selected.save!
    result = report(selected)
    assert_equal 120, result.expenses
    assert_equal(-120, result.surplus)
    assert_equal 0, result.deposits
    assert_equal 0, @workspace.bookkeeping_entries.count
    assert_includes result.csv, "Datierte Arbeitstageliste"
    selected.update!(home_days: 365)
    assert_equal 1260, report(selected).expenses
    selected.update!(home_office_method: "none")
    assert_equal 0, report(selected).expenses
  end

  test "annual office allowance is reduced by whole months without eligibility" do
    selected = policy(home_office_method: "annual", home_months: 7)
    selected.save!
    assert_equal 735, report(selected).field_totals["expense_home_office"]
    assert_equal 0, report(selected).field_totals["expense_home_days"]
    selected.update!(home_months: 12)
    assert_equal 1260, report(selected).expenses
  end

  test "overlaps require allocation rather than adding a second deduction" do
    @workspace.euer_adjustments.create!(year: 2026, field_key: "expense_home_office", amount: 100, description: "Bereits ermittelt")
    selected = policy
    assert_not selected.valid?
    assert_includes selected.errors.full_messages.join, "Überschneidungen"
    @workspace.euer_adjustments.destroy_all
    selected.save!
    @workspace.euer_adjustments.create!(year: 2026, field_key: "expense_home_days", amount: 60, description: "Spätere Übernahme")
    result = report(selected)
    assert_equal 60, result.expenses
    assert_includes result.warnings.join, "wird nicht angewendet"
  end

  test "confirmation and evidence are required and a profession allowance cannot be combined" do
    assert_not policy(home_eligibility_confirmed: false).valid?
    assert_not policy(home_basis: "").valid?
    assert_not policy(home_days: "2.5").valid?
    assert_not policy(home_days: 366).valid?
    assert_not policy(home_months: 13).valid?
    @statement.update!(details: { "legal_form" => "Einzelunternehmen", "income_type" => "3" })
    selected = policy(deduction_method: "writer_main", eligibility_confirmed: true)
    assert_not selected.valid?
    assert_includes selected.errors.full_messages.join, "nicht zusätzlich"
  end
end
