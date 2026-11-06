require "test_helper"

class SevdeskEuerImportTest < ActiveSupport::TestCase
  def text = File.read(file_fixture("sevdesk_euer.txt"))

  test "positions resolve across outdated line numbering without importing totals twice" do
    result = SevdeskEuerImport.text(text)
    assert_equal 2026, result.year
    assert_equal Date.new(2026, 9, 29), result.covered_through
    assert_equal "9.99", result.amounts["expense_goods"]
    assert_equal "100.0", result.amounts["income_small_details"]
    report = BookkeepingReport.new(BookkeepingEntry.none, result.year, imports: [ BookkeepingImport.new(year: result.year, amounts: result.amounts) ])
    assert_equal 1000, report.income
    assert_equal 120, report.expenses
    assert_equal 880, report.surplus
    assert_equal 20, report.withdrawals
    assert_equal 30, report.deposits
    assert_includes result.notes, "Zeilennummern eines anderen Formularjahrs (erkannt: 2025)"
    assert_includes result.notes, "Stand allein beweist nicht"
  end

  test "unknown ambiguous inconsistent and incomplete documents fail entirely" do
    [ text.sub("1.000,00 €", "1.001,00 €"), text.sub("880,00 €", "881,00 €"),
      text.sub("         183", "         999"), text.sub("Seite: 2 / 4", "Seite: 1 / 4"),
      text.sub("Seite: 2 / 4", ""), text.gsub("1 / 4", "1 / 25"),
      text.sub("2. Betriebsausgaben", "Unbekannter Bereich"), text.sub("Zeitraum: 01.01.2026", "Zeitraum: 01.01.2025"),
      text.sub("       9,99 €", "       9,999 €"), text.sub("27         100", "99         100"),
      text.sub("Waren, Rohstoffe und Hilfsstoffe", "Dupliziert 27         100        9,99 €\nWaren, Rohstoffe und Hilfsstoffe"),
      "%PDF-1.7 scan without selectable text" ].each do |input|
      assert_raises(EuerTotalsImport::InvalidFile) { SevdeskEuerImport.text(input) }
    end
  end

  test "after year end report proposes year end instead of export date" do
    result = SevdeskEuerImport.text(text.gsub("Stand: 29.09.2026", "Stand: 15.02.2027"))
    assert_equal Date.new(2026, 12, 31), result.covered_through
  end

  test "rejects oversized files and non PDF input before starting extraction" do
    upload = Struct.new(:size, :tempfile).new(11.megabytes, nil)
    assert_raises(EuerTotalsImport::InvalidFile) { SevdeskEuerImport.pdf(upload) }
    file = Tempfile.new("not-a-pdf")
    file.write("not a PDF")
    file.flush
    assert_raises(EuerTotalsImport::InvalidFile) { SevdeskEuerImport.pdf(Struct.new(:size, :tempfile).new(file.size, file)) }
  ensure
    file&.close!
  end
end
