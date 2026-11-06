require "test_helper"

class EuerPreparationCheckTest < ActiveSupport::TestCase
  def basic_details
    { "taxpayer_name" => "Beispiel", "first_name" => "Erika", "tax_number" => "12/345/67890", "activity" => "Beratung",
      "legal_form" => "Einzelunternehmen", "income_type" => "2", "owner" => "1", "property_disposal" => "2" }
  end

  def check(details, year: 2026, warnings: [])
    EuerPreparationCheck.new(Struct.new(:details, :year, :warnings).new(details, year, warnings))
  end

  test "ordinary business needs basic data but no assumed special elections" do
    assert_empty check(basic_details).missing_keys
    assert_empty check(basic_details).notices
    assert_empty check(basic_details).relevant_fields
    assert_includes check({}).missing_keys, "income_type"
    assert_not_includes check({}).missing_keys, "termination"
    assert_not_includes check({}).missing_keys, "business_id"
    assert_not_includes check({}).missing_keys, "period_start"
    assert_includes check(basic_details.except("property_disposal")).missing_keys, "property_disposal"
    assert_includes check(basic_details.except("first_name")).missing_keys, "first_name"
    assert_not_includes check(basic_details.except("first_name").merge("legal_form" => "GmbH")).missing_keys, "first_name"
  end

  test "agriculture requires period information and only offers positions available that year" do
    details = basic_details.merge("income_type" => "1")
    assert_equal %w[period_start period_end], check(details).missing_keys
    assert_includes check(details).notices.join, "Anlage LuF"
    assert_includes check(details).notices.join, "keine Umsatzsteuerberechnung"
    assert_includes check(details).relevant_fields, "expense_livestock_reserve"
    assert_not_includes check(details, year: 2025).relevant_fields, "expense_livestock_reserve"
    assert_empty check(details, year: 2027).relevant_fields
    calendar_period = details.merge("period_start" => "2026-01-01", "period_end" => "2026-12-31")
    assert_empty check(calendar_period).missing_keys
    assert_not_includes check(calendar_period).notices, EuerPreparationCheck::CALENDAR_WARNING
  end

  test "special cases disclose missing automation and deduplicate calendar warnings" do
    details = basic_details.merge("legal_form" => "GbR", "owner" => "3", "termination" => "1",
      "property_disposal" => "1", "period_start" => "2026-07-01", "period_end" => "2027-06-30", "tax_number" => "DE123456789")
    warnings = check(details, warnings: [ EuerPreparationCheck::CALENDAR_WARNING ]).warnings
    assert_equal 1, warnings.count(EuerPreparationCheck::CALENDAR_WARNING)
    %w[Rechtsform Betriebsbeendigung Grundstücksabgang Betriebsinhaber Steuernummer].each do |term|
      assert_includes warnings.join, term
    end
    assert_includes check(basic_details.merge("legal_form" => "GmbH")).notices.join, "ob die EÜR anwendbar ist"
    assert_empty check(basic_details.merge("legal_form" => "Angehörige(r) der freien Berufe", "income_type" => "3")).notices
  end

  test "business metadata never silently changes recorded amounts and warnings travel with CSV" do
    workspace = Workspace.create!
    workspace.bookkeeping_entries.create!(kind: "expense", category: "expense_other", paid_on: "2026-10-12", amount: "100", description: "Betriebliche Kosten")
    statement = workspace.euer_statements.create!(year: 2026, details: basic_details)
    report = -> { BookkeepingReport.new(workspace.bookkeeping_entries, 2026, statement: statement) }
    totals = [ report.call.income, report.call.expenses, report.call.surplus ]
    statement.update!(details: basic_details.merge("income_type" => "1", "termination" => "2"))
    assert_equal totals, [ report.call.income, report.call.expenses, report.call.surplus ]
    assert_includes report.call.csv, "Anlage LuF"
    assert_includes report.call.csv, "Betriebsbeendigung"
    assert_includes report.call.csv, "Betriebsangaben prüfen"
  end
end
