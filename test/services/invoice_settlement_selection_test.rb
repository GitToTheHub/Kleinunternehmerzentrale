require "test_helper"

class InvoiceSettlementSelectionTest < ActiveSupport::TestCase
  def attrs(amount)
    invoices(:one).attributes.slice(*Invoice::COPIED_ATTRIBUTES).merge(
      "issued_on" => Date.current, "service_on" => Date.current, "customer_id" => nil,
      "payment_method" => "other", "invoice_number_format" => InvoiceNumber::DEFAULT_FORMAT,
      "invoice_lines_attributes" => { "0" => { "description" => "Vereinbarte Umsetzung", "quantity" => "1", "unit_price" => amount.to_s, "unit_code" => "LS", "tax_rate" => "0" } })
  end

  def direct(amount, workspace: workspaces(:one), root: nil, paid: true, name: nil)
    input = attrs(amount).merge("billing_kind" => "advance", "allocation_basis" => "direct", "paid" => paid, "received_on" => Date.current)
    input.merge!("billing_root_id" => root.id, "customer_id" => root.customer_id, "customer_update_mode" => "invoice_only") if root
    input["buyer_name"] = name if name
    invoice = OrderInvoicePreparation.new(workspace, input).call
    invoice.record_initial_payment = true
    workspace.with_lock { invoice.save! }
    invoice
  end

  def final(ids, customer, amount = 800)
    OrderInvoicePreparation.new(workspaces(:one), attrs(amount).merge("billing_kind" => "final", "customer_id" => customer.id,
      "customer_update_mode" => "invoice_only", "settlement_invoice_ids" => ids)).call
  end

  test "direct advances need no overall order and final selects independent paid advances once" do
    first = direct(300)
    second = direct(100)
    assert_nil first.sales_document_id
    assert_equal "direct", first.allocation_mode
    assert_equal 300.to_d, first.total
    assert_equal 2, InvoiceSettlementSelection.groups(first.workspace).length
    invoice = final([ first.id, second.id, first.id ], first.customer)
    assert_equal 400.to_d, invoice.tap(&:valid?).deducted_total
    first.workspace.with_lock { invoice.save! }
    assert_equal 800.to_d, invoice.total
    assert_equal 400.to_d, invoice.payment_total
    assert_equal [ first.id, second.id ].sort, invoice.deducted_payments.map { |entry| entry["invoice_id"] }.sort
    assert first.reload.settled_in_final?
    assert second.reload.settled_in_final?
    assert_empty InvoiceSettlementSelection.groups(first.workspace)
    assert_not final([ first.id ], first.customer).valid?
    assert_not first.payment_entry.update(description: "Geändert")
    assert_not first.build_cancellation.valid?
    xml = Nokogiri::XML(XrechnungGenerator.new(invoice).call)
    assert_equal 400.to_d, xml.xpath("//*[local-name()='DuePayableAmount']").text.to_d
    assert_equal 400.to_d, xml.xpath("//*[local-name()='TotalPrepaidAmount']").text.to_d
    cancellation = invoice.build_cancellation
    cancellation.save!
    assert_equal(-400.to_d, cancellation.payment_total)
    assert_not first.reload.settled_in_final?
    assert first.payment_entry.update(description: "Wieder änderbar")
    assert final([ first.id, second.id ], first.customer).valid?
    assert_equal 2, InvoiceSettlementSelection.groups(first.workspace).length
  end

  test "related advances are settled together and an unpaid sibling prevents finalization" do
    root = direct(300)
    child = direct(100, root: root, paid: false)
    assert_empty InvoiceSettlementSelection.groups(root.workspace)
    assert_not final([ root.id ], root.customer).valid?
    child.workspace.bookkeeping_entries.create!(kind: "income", category: "income_small", invoice: child,
      paid_on: Date.current, amount: 100, description: "Zahlung", payment_account: "business")
    assert_equal 1, InvoiceSettlementSelection.groups(root.workspace).length
    invoice = final([ root.id ], root.customer)
    invoice.save!
    assert_equal 400.to_d, invoice.deducted_total
    assert child.reload.settled_in_final?
    direct_input = attrs(50).merge("billing_kind" => "progress", "billing_root_id" => root.id, "customer_id" => root.customer_id, "customer_update_mode" => "invoice_only", "allocation_basis" => "direct")
    assert_not OrderInvoicePreparation.new(root.workspace, direct_input).call.valid?
  end

  test "selection rejects other customers workspaces invalid ids and over-deductions" do
    first = direct(300)
    other_customer = direct(100, name: "Andere Firma")
    other_workspace = direct(100, workspace: Workspace.create!)
    [ [ other_customer.id ], [ other_workspace.id ], [ invoices(:one).id ], [ "invalid" ] ].each do |ids|
      assert_not final(ids, first.customer).valid?, ids.inspect
    end
    assert_not final([ first.id ], first.customer, 299).valid?
    assert_not final([], first.customer).valid?
    record = final([ first.id ], first.customer)
    record.billing_kind = "regular"
    assert_not record.valid?
  end
end
