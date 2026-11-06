require "test_helper"

class OrderPositionAllocationTest < ActiveSupport::TestCase
  def attrs
    invoices(:one).attributes.slice(*Invoice::COPIED_ATTRIBUTES).merge(
      "issued_on" => Date.current.to_s, "service_on" => Date.current.to_s, "customer_id" => nil,
      "order_based" => "1", "billing_kind" => "advance", "allocation_basis" => "positions",
      "invoice_lines_attributes" => {
        "17" => { "description" => "Material", "quantity" => "1", "unit_price" => "300,00", "unit_code" => "LS", "tax_rate" => "0" },
        "42" => { "description" => "Anpassungen", "quantity" => "1", "unit_price" => "500,00", "unit_code" => "LS", "tax_rate" => "0" }
      },
      "position_allocations" => { "17" => { "mode" => "percent", "value" => "50" }, "42" => { "mode" => "amount", "value" => "125,00" } })
  end

  def prepare(input = attrs)
    OrderInvoicePreparation.new(workspaces(:one), input).call
  end

  test "positions mix percentages and fixed amounts without changing the agreed prices" do
    invoice = prepare
    assert_equal [ 150.to_d, 125.to_d ], invoice.invoice_lines.map(&:line_total)
    assert_equal 275.to_d, invoice.total
    assert_equal 800.to_d, invoice.order_total
    assert_equal "positions", invoice.allocation_mode
    invoice.workspace.with_lock { invoice.save! }
    assert_equal [ 300.to_d, 500.to_d ], invoice.sales_document.invoice_view.invoice_lines.map(&:line_total)
    assert_equal [ 0, 1 ], invoice.reload.order_snapshot["allocations"].map { |entry| entry["source_index"] }
    assert_equal "50.0", invoice.order_snapshot["allocations"][0]["value"]
    xml = Nokogiri::XML(XrechnungGenerator.new(invoice).call)
    assert_equal 275.to_d, xml.xpath("//*[local-name()='DuePayableAmount']").text.to_d
    assert_equal 2, xml.xpath("//*[local-name()='IncludedSupplyChainTradeLineItem']").length
    cancellation = invoice.build_cancellation
    cancellation.save!
    assert_equal(-275.to_d, cancellation.total)
    assert_equal invoice.order_snapshot, cancellation.order_snapshot
    assert_equal [ 0.to_d, 0.to_d ], OrderPositionAllocation.used(invoice.sales_document, [ 300.to_d, 500.to_d ])
  end

  test "zero skips a position while invalid amounts unknown keys and missing entries are rejected" do
    data = attrs
    data["position_allocations"]["17"]["value"] = "0"
    assert_equal 125.to_d, prepare(data).total
    assert_equal 1, prepare(data).invoice_lines.length
    [ "101", "-1", "abc", "12,345", "" ].each do |value|
      data = attrs
      data["position_allocations"]["17"]["value"] = value
      assert_not prepare(data).valid?, value
    end
    data = attrs
    data["position_allocations"]["42"]["value"] = "500,01"
    assert_not prepare(data).valid?
    data = attrs
    data["position_allocations"].delete("42")
    assert_not prepare(data).valid?
    data = attrs
    data["position_allocations"]["999"] = { "mode" => "amount", "value" => "100" }
    assert_not prepare(data).valid?
    data = attrs
    data["position_allocations"].each_value { |entry| entry["value"] = "0" }
    assert_not prepare(data).valid?
  end

  test "position limits include previous overall payments and canonical order prices" do
    first = prepare(attrs.merge("allocation_basis" => "total", "allocation_mode" => "percent", "allocation_percent" => "50"))
    first.workspace.with_lock { first.save! }
    order = first.sales_document
    assert_equal [ 150.to_d, 250.to_d ], OrderPositionAllocation.used(order, [ 300.to_d, 500.to_d ])
    # Previously saved overall advances have no position allocation snapshot.
    Invoice.where(id: first.id).update_all(order_snapshot: first.order_snapshot.except("allocations"))
    assert_equal [ 150.to_d, 250.to_d ], OrderPositionAllocation.used(order, [ 300.to_d, 500.to_d ])
    data = attrs.merge("sales_document_id" => order.id, "customer_id" => first.customer_id, "customer_update_mode" => "invoice_only",
      "position_allocations" => { "0" => { "mode" => "amount", "value" => "151" }, "1" => { "mode" => "amount", "value" => "0" } })
    data["invoice_lines_attributes"].each_value { |entry| entry["unit_price"] = "1" }
    assert_not prepare(data).valid?
    data["position_allocations"]["0"]["value"] = "150"
    second = prepare(data)
    assert second.valid?, second.errors.full_messages.join
    assert_equal 150.to_d, second.total
    assert_equal 800.to_d, second.order_total
    second.workspace.with_lock { second.save! }
    assert_equal [ 300.to_d, 250.to_d ], OrderPositionAllocation.used(order, [ 300.to_d, 500.to_d ])
    third = prepare(data.merge("allocation_basis" => "total", "allocation_mode" => "amount", "allocation_amount" => "250"))
    assert third.valid?, third.errors.full_messages.join
    assert_equal [ "0.0", "250.0" ], third.order_snapshot["allocations"].map { |entry| entry["amount"] }
  end

  test "cent distribution preserves totals and uses largest remainders deterministically" do
    assert_equal [ 0.01.to_d, 0.01.to_d, 0.to_d ], OrderPositionAllocation.distribute(0.02.to_d, [ 0.09.to_d, 0.07.to_d, 0.04.to_d ])
    data = attrs
    data["invoice_lines_attributes"].each_value { |entry| entry["unit_price"] = "0,03" }
    data["position_allocations"].each_value { |entry| entry.merge!("mode" => "percent", "value" => "50") }
    invoice = prepare(data)
    assert_equal [ 0.02.to_d, 0.02.to_d ], invoice.invoice_lines.map(&:line_total)
    assert_equal 0.04.to_d, invoice.total
  end
end
