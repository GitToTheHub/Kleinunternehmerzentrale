require "test_helper"

class InvoiceBillingOverviewTest < ActiveSupport::TestCase
  test "groups partial amounts and excludes cancellations and other orders" do
    first = Invoice.new(id: 1, billing_kind: "advance", sales_document_id: 10, order_snapshot: { "total" => "800" })
    first.invoice_lines.build(description: "Auftrag", quantity: 1, unit_price: 400)
    second = Invoice.new(id: 2, billing_kind: "progress", sales_document_id: 10, order_snapshot: { "total" => "800" })
    second.invoice_lines.build(description: "Auftrag", quantity: 1, unit_price: 200)
    cancelled = Invoice.new(id: 3, billing_kind: "advance", sales_document_id: 10)
    cancelled.cancellation = Invoice.new(cancelled_invoice_id: 3)
    other = Invoice.new(id: 4, billing_kind: "advance")
    other.invoice_lines.build(description: "Direkt", quantity: 1, unit_price: 100)

    summary = InvoiceBillingOverview.call([ first, second, cancelled, other ])
    assert_equal({ total: 800.to_d, billed: 600.to_d, count: 2 }, summary[1])
    assert_equal summary[1], summary[2]
    assert_nil summary[3]
    assert_equal({ total: nil, billed: 100.to_d, count: 1 }, summary[4])
  end
end
