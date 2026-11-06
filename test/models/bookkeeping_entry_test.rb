require "test_helper"

class BookkeepingEntryTest < ActiveSupport::TestCase
  test "German amounts preserve cents and invalid precision is rejected" do
    entry = Workspace.create!.bookkeeping_entries.new(paid_on: "2026-10-12", kind: "income", description: "Zahlung", amount: "1.234,56")
    assert entry.valid?
    assert_equal BigDecimal("1234.56"), entry.amount
    [ "1.234", "12,345", "abc", "0", "-20", "12x", "1e3", "1..234,56", "1.23,45" ].each do |amount|
      entry.amount = amount
      assert_not entry.valid?, amount
    end
  end

  test "category tax split and year must match the type of transaction" do
    entry = Workspace.create!.bookkeeping_entries.new(paid_on: "2026-10-12", kind: "income", description: "Zahlung", amount: 100)
    entry.category = "expense_other"
    assert_not entry.valid?
    entry.category = "income_small"
    entry.vat_amount = 19
    assert_not entry.valid?
    entry.category = "income_taxable"
    entry.vat_amount = 101
    assert_not entry.valid?
    entry.vat_amount = 19
    entry.tax_year = 2024
    assert_not entry.valid?
    entry.tax_year = 2025
    assert entry.valid?, entry.errors.full_messages.to_sentence
    entry.kind = "noncash_withdrawal"
    entry.category = "other_withdrawal"
    assert_not entry.valid?, "noncash movements must use their actual year"
  end

  test "cash allocation requires a conscious choice and a valid private share" do
    entry = Workspace.create!.bookkeeping_entries.new(paid_on: "2026-10-12", kind: "income", description: "Barzahlung", amount: "100,01", payment_account: "cash")
    assert_not entry.valid?
    assert entry.errors[:cash_usage].any?
    entry.cash_usage = "split"
    [ nil, "0", "100,01", "100,02", "-1", "1,001", "12abc" ].each do |value|
      entry.cash_private_amount = value
      assert_not entry.valid?, value.inspect
    end
    entry.cash_private_amount = "33,34"
    assert entry.valid?, entry.errors.full_messages.to_sentence
    assert_equal BigDecimal("33.34"), entry.income_private_withdrawal
    entry.save!
    entry.update!(cash_usage: "private")
    assert_equal BigDecimal("100.01"), entry.reload.cash_private_amount
    entry.update!(cash_usage: "business")
    assert_equal 0, entry.reload.cash_private_amount
    entry.update!(payment_account: "private")
    assert_nil entry.reload.cash_usage
    assert_nil entry.cash_private_amount
    assert_equal BigDecimal("100.01"), entry.income_private_withdrawal
    entry.assign_attributes(payment_account: "cash", cash_usage: "business", kind: "expense", category: "expense_other")
    assert_not entry.valid?
  end

  test "year report excludes private movements from surplus and escapes CSV formulas" do
    workspace = Workspace.create!
    { income: 100, expense: 30, deposit: 50, withdrawal: 20 }.each do |kind, amount|
      workspace.bookkeeping_entries.create!(paid_on: "2026-01-01", kind: kind, amount: amount, description: "=Formula")
    end
    workspace.bookkeeping_entries.create!(paid_on: "2025-12-31", kind: "income", amount: 900, description: "Vorjahr")
    report = BookkeepingReport.new(workspace.bookkeeping_entries, 2026)
    assert_equal 70, report.surplus
    assert_equal 50, report.totals.fetch("deposit")
    assert_equal 20, report.totals.fetch("withdrawal")
    assert_equal 4, report.entries.count
    assert_includes report.csv, "'=Formula"
    assert_not_includes report.csv, "2025-12-31"
    workspace.erase!
    assert_equal 0, BookkeepingEntry.where(workspace_id: workspace.id).count
  end
end
