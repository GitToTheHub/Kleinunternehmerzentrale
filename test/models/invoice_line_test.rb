require "test_helper"

class InvoiceLineTest < ActiveSupport::TestCase
  test "German price inputs retain cents and reject malformed amounts" do
    line = InvoiceLine.new(unit_price: "1.234,56")
    assert_equal BigDecimal("1234.56"), line.unit_price
    line.valid?
    assert_empty line.errors[:unit_price]
    [ "50,555", "50abc", "1.234", "1e3" ].each do |value|
      line.unit_price = value
      line.valid?
      assert line.errors[:unit_price].any?, value
    end
  end
  test "Pauschalen haben genau eine Menge und Stornopauschalen minus eins" do
    invoice = Invoice.new
    line = invoice.invoice_lines.build(description: "Projekt", quantity: 8, unit_price: 120, unit_code: "LS")
    assert line.valid?
    assert_equal 1, line.quantity
    assert_equal 120, line.line_total
    invoice.cancelled_invoice = invoices(:one)
    assert line.valid?
    assert_equal(-1, line.quantity)
    assert_equal(-120, line.line_total)
  end
end
