require "test_helper"

class BookkeepingReportTest < ActiveSupport::TestCase
  setup { @workspace = Workspace.create! }

  def entry(**attributes)
    @workspace.bookkeeping_entries.create!({ paid_on: "2026-10-12", kind: "income", category: "income_small", description: "Vorgang", amount: 100 }.merge(attributes))
  end

  def report(year = 2026)
    BookkeepingReport.new(@workspace.bookkeeping_entries, year, assets: @workspace.business_assets, adjustments: @workspace.euer_adjustments)
  end

  test "cash income stays whole and only the private cash share counts as withdrawal" do
    entry(payment_account: "cash", cash_usage: "business", amount: "100,01")
    entry(payment_account: "cash", cash_usage: "private", amount: "50,02")
    original = entry(payment_account: "cash", cash_usage: "split", cash_private_amount: "33,34", amount: "100,01")
    entry(**original.refund_attributes, original_entry: original, payment_account: "cash", cash_usage: "split", cash_private_amount: "10,01", amount: "25,02")
    assert_equal BigDecimal("225.02"), report.income
    assert_equal BigDecimal("225.02"), report.surplus
    assert_equal BigDecimal("73.35"), report.withdrawals
    assert_equal BigDecimal("73.35"), report.automatic_money_movements("withdrawal").sum { |row| row[:amount] }
    assert_includes report.csv, "Bargeld privat EUR"
    assert_includes report.csv, "33,34"
    other = Workspace.create!
    other.bookkeeping_entries.create!(paid_on: "2026-10-12", kind: "income", description: "Andere Barzahlung", amount: 999, payment_account: "cash", cash_usage: "private")
    assert_equal BigDecimal("73.35"), report.withdrawals
    assert_equal 0, report(2025).withdrawals
  end

  test "cash withdrawals follow payment year rather than differing income tax year" do
    entry(paid_on: "2027-01-05", tax_year: 2026, payment_account: "cash", cash_usage: "split", cash_private_amount: "33,34")
    assert_equal 100, report(2026).income
    assert_equal 0, report(2026).withdrawals
    assert_equal 0, report(2027).income
    assert_equal BigDecimal("33.34"), report(2027).withdrawals
  end

  test "VAT separation meals deduction private accounts and refunds reconcile" do
    entry(category: "income_taxable", amount: 1190, vat_amount: 190, payment_account: "private")
    entry(kind: "expense", category: "expense_meals", amount: 119, vat_amount: 19, payment_account: "private")
    entry(kind: "expense", category: "expense_meals", amount: 11.9, vat_amount: 1.9, reversal: true, payment_account: "private")
    assert_equal 1190, report.income
    assert_equal 63, report.field_totals["expense_meals"]
    assert_equal 27, report.field_totals["meals_disallowed"]
    assert_equal BigDecimal("17.1"), report.field_totals["input_vat"]
    assert_equal BigDecimal("80.1"), report.expenses
    assert_equal BigDecimal("1109.9"), report.surplus
    assert_equal 1190, report.withdrawals
    assert_equal BigDecimal("107.1"), report.deposits
  end

  test "stock contributions and goods withdrawals affect profit and equity" do
    entry(kind: "noncash_deposit", category: "expense_goods", amount: 300)
    entry(kind: "noncash_withdrawal", category: "other_withdrawal", amount: 238, vat_amount: 38)
    assert_equal 300, report.deposits
    assert_equal 238, report.withdrawals
    assert_equal 238, report.income
    assert_equal 300, report.expenses
    assert_equal(-62, report.surplus)
  end

  test "ten day year override does not move the actual private equity payment" do
    entry(paid_on: "2027-01-05", tax_year: 2026, kind: "expense", category: "vat_payment", amount: 100, payment_account: "private")
    assert_equal 100, report(2026).expenses
    assert_equal 0, report(2026).deposits
    assert_equal 0, report(2027).expenses
    assert_equal 100, report(2027).deposits
  end

  test "purchased assets deduct only depreciation and paid input VAT and add private purchase equity" do
    @workspace.business_assets.create!(name: "Maschine", acquired_on: "2026-10-12", paid_on: "2027-01-01", cost: 1200, input_vat: 228, useful_life: 3, payment_account: "private")
    assert_equal 100, report.expenses
    assert_equal 0, report.deposits
    assert_equal 628, report(2027).expenses
    assert_equal 1428, report(2027).deposits
  end

  test "profit adjustments respect field signs and cannot overwrite computed totals" do
    entry(amount: 1000)
    @workspace.euer_adjustments.create!(year: 2026, field_key: "iab_deduction", amount: 300, description: "Fachlich ermittelt")
    @workspace.euer_adjustments.create!(year: 2026, field_key: "method_change", amount: -100, description: "Übergangsverlust")
    @workspace.euer_adjustments.create!(year: 2026, field_key: "interest_addback", amount: 50, description: "Anlage SZ")
    assert_equal 1000, report.income
    assert_equal 650, report.surplus
    invalid = @workspace.euer_adjustments.new(year: 2026, field_key: "profit_total", amount: 100, description: "Ungültig")
    assert_not invalid.valid?
  end

  test "EÜR and AVEÜR use separate verified year mappings and omit mappings for other years" do
    assert_equal 27, EuerFields.line("expense_goods", 2025)
    assert_equal 29, EuerFields.line("expense_goods", 2026)
    assert_equal 33, EuerFields.line("afa_movable", 2025)
    assert_equal 34, EuerFields.line("afa_movable", 2026)
    assert_equal 106, EuerFields.line("withdrawals", 2025)
    assert_equal 107, EuerFields.line("withdrawals", 2026)
    assert_nil EuerFields.line("afa_movable", 2027)
    @workspace.business_assets.create!(name: "Computer", acquired_on: "2025-10-01", paid_on: "2025-10-01", cost: 1200, useful_life: 3)
    rows = report.aveuer_rows.index_by { |row| row[:number] }
    assert_equal 1200, rows[410][:amount]
    assert_equal 1100, rows[411][:amount]
    assert_equal 400, rows[414][:amount]
    assert_equal 700, rows[416][:amount]
    assert_equal 52, rows[414][:line]
    assert report(2027).aveuer_rows.all? { |row| row[:line].nil? && row[:number].nil? }
    assert report(2027).warnings.any? { |text| text.include?("keine amtlich geprüfte") }
  end

  test "export protects all free text and includes book values plus manual depreciation warning" do
    entry(description: "=evil", reference: "+evil")
    @workspace.business_assets.create!(name: "@evil", acquired_on: "2026-10-12", paid_on: "2026-10-12", cost: 1200, depreciation_method: "manual")
    @workspace.euer_adjustments.create!(year: 2026, field_key: "expense_home_days", amount: 6, description: "=evil")
    assert_includes report.csv, "'=evil"
    assert_includes report.csv, "'+evil"
    assert_includes report.csv, "'@evil"
    assert_includes report.csv, "AVEÜR-Gruppe"
    assert report.warnings.any? { |text| text.include?("fehlt der Jahresbetrag") }
    assert_equal 6, report.expenses
  end

  test "empty year renders valid zero totals and CSV" do
    assert_equal 0, report.surplus
    assert_includes report.csv, "0,0"
  end
  test "small business report deducts gross expenses and omits regular tax positions from CSV" do
    entry(amount: 500)
    entry(kind: "expense", category: "expense_goods", amount: 119)
    entry(kind: "expense", category: "expense_meals", amount: 119)
    assert_equal BigDecimal("202.3"), report.expenses
    assert_equal BigDecimal("297.7"), report.surplus
    EuerFields::REGULAR_TAX_KEYS.each do |key|
      assert_not_includes report.display_fields.map(&:key), key
      assert_not_includes report.csv, EuerFields::DEFINITIONS.fetch(key).label
    end
    assert_not_includes report.csv, "Steueranteil EUR"
    assert_not report.legacy_tax_data?
  end

  test "nonzero older tax positions remain visible in exports and trigger review" do
    entry(category: "income_taxable", amount: 119, vat_amount: 19)
    assert_includes report.display_fields.map(&:key), "income_taxable"
    assert_includes report.display_fields.map(&:key), "vat_collected"
    assert_includes report.csv, "Steueranteil EUR"
    assert report.warnings.any? { |text| text.include?("ältere Angaben zur Regelbesteuerung") }
    assert_equal 119, report.income
  end
end
