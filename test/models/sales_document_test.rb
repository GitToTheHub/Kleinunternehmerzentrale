require "test_helper"

class SalesDocumentTest < ActiveSupport::TestCase
  def attributes_for_scope
    invoices(:one).attributes.slice(*Invoice::COPIED_ATTRIBUTES).merge(
      "issued_on" => Date.current.to_s, "service_on" => Date.current.to_s, "customer_id" => nil,
      "invoice_lines_attributes" => { "0" => { "description" => "Anpassungen am Teilnehmermanagement", "details" => "<p>Vereinbarte Anpassungen</p>", "quantity" => "1", "unit_price" => "800,00", "unit_code" => "LS", "tax_rate" => "0" } })
  end

  test "neue Dokumente verwenden die Rechnungsvorgabe und speichern Anpassungen nur lokal" do
    workspace = workspaces(:one)
    profile = workspace.create_business_profile!(invoice_number_format: "[Rechnungsart]-[Jahr]-[Fortlaufendenummer]-NEU")
    %w[offer order].each do |kind|
      document = workspace.sales_documents.new(kind: kind, document_date: Date.current, data: SalesDocument.input_data(attributes_for_scope).except("invoice_number_format"))
      assert_equal profile.invoice_number_format, document.number_format
      document.data["invoice_number_format"] = "[Rechnungsart]-[Jahr]-[Fortlaufendenummer]-EINZELN"
      document.save!
      assert_equal "[Rechnungsart]-[Jahr]-[Fortlaufendenummer]-NEU", profile.reload.invoice_number_format
      assert_match(/-EINZELN\z/, document.document_number)
    end
  end

  test "gemeinsames Nummernformat vergibt AN und AU mit eigenen Zaehlern und behaelt bestehende Nummern" do
    workspace = workspaces(:one)
    data = SalesDocument.input_data(attributes_for_scope.merge("invoice_number_format" => "[Rechnungsart]-[Kundenkürzel]-[Jahr]-[Fortlaufendenummer]", "buyer_abbreviation" => "KU"))
    offer = workspace.sales_documents.new(kind: "offer", document_date: Date.current, data: data)
    offer.invoice_number_last = "99"
    offer.save!
    assert_equal "AN-KU-#{Date.current.year}-0100", offer.document_number
    assert_equal data["invoice_number_format"], offer.reload.number_format
    original = offer.document_number
    offer.invoice_number_last = "99"
    offer.update!(data: offer.data.merge("title" => "Angepasst"))
    assert_equal original, offer.document_number
    order = offer.accept!
    assert_equal "AU-KU-#{Date.current.year}-0001", order.document_number
    assert_equal original, offer.reload.document_number
    invalid = workspace.sales_documents.new(kind: "order", document_date: Date.current, data: data.merge("buyer_abbreviation" => ""))
    assert_not invalid.valid?
    assert_includes invalid.errors.full_messages.join, "Kundenkürzel"
  end

  test "Angebot wird einmalig als eigenstaendiger Auftrag uebernommen" do
    workspace = workspaces(:one)
    offer = workspace.sales_documents.create!(kind: "offer", document_date: Date.current, data: SalesDocument.input_data(attributes_for_scope))
    assert_match(/\AAN-\d{4}-0001\z/, offer.document_number)
    assert_equal 800.to_d, offer.total_amount
    order = offer.accept!
    assert_equal order, offer.accept!
    assert_equal offer.data, order.data
    assert_equal offer.id, order.source_offer_id
    assert_not offer.update(data: offer.data.merge("title" => "Geändert"))
  end

  test "direkte Anzahlung berechnet 50 Prozent ohne Preise des Auftrags zu veraendern" do
    workspace = workspaces(:one)
    invoice = OrderInvoicePreparation.new(workspace, attributes_for_scope.merge("order_based" => "1", "billing_kind" => "advance", "allocation_mode" => "percent", "allocation_percent" => "50")).call
    assert_equal 400.to_d, invoice.total
    assert_equal 800.to_d, invoice.order_total
    assert_difference "SalesDocument.count", 1 do
      workspace.with_lock { invoice.save! }
    end
    order = invoice.sales_document.reload
    assert_equal 800.to_d, order.total_amount
    assert_equal 800.to_d, order.invoice_view.invoice_lines.sole.unit_price
    assert_equal 400.to_d, invoice.reload.payment_total
    next_advance = OrderInvoicePreparation.new(workspace, attributes_for_scope.merge("sales_document_id" => order.id, "billing_kind" => "advance", "allocation_mode" => "percent", "allocation_percent" => "50")).call
    assert_equal [ { "number" => invoice.invoice_number, "amount" => "400.0", "paid_amount" => "0.0" } ], next_advance.order_snapshot.fetch("previous_invoices")
    assert_equal 400.to_d, next_advance.payment_total
    assert_not order.update(data: order.data.merge("title" => "Geändert"))
    cancellation = invoice.build_cancellation
    cancellation.save!
    assert_equal(-400.to_d, cancellation.total)
    assert_equal order.id, cancellation.sales_document_id
  end

  test "Betrag und Prozentsatz werden serverseitig geprueft" do
    %w[0 101 ungueltig].each do |value|
      invoice = OrderInvoicePreparation.new(workspaces(:one), attributes_for_scope.merge("order_based" => "1", "billing_kind" => "advance", "allocation_mode" => "percent", "allocation_percent" => value)).call
      assert_not invoice.valid?, value
    end
    invoice = OrderInvoicePreparation.new(workspaces(:one), attributes_for_scope.merge("order_based" => "1", "billing_kind" => "advance", "allocation_mode" => "amount", "allocation_amount" => "400,00")).call
    assert_equal 400.to_d, invoice.total
  end

  test "fremde Auftraege bleiben isoliert und normale Rechnungen brauchen keinen Auftrag" do
    other = Workspace.create!
    order = other.sales_documents.create!(kind: "order", document_date: Date.current, data: SalesDocument.input_data(attributes_for_scope))
    assert_raises ActiveRecord::RecordNotFound do
      OrderInvoicePreparation.new(workspaces(:one), attributes_for_scope.merge("sales_document_id" => order.id)).call
    end
    invoice = OrderInvoicePreparation.new(workspaces(:one), attributes_for_scope.merge("order_based" => "1")).call
    assert_nil invoice.sales_document
    assert_equal 800.to_d, invoice.total
  end
  test "geplanter Zeitraum braucht einen Beginn und unbekannte Daten werden ignoriert" do
    attrs = attributes_for_scope.merge("service_on" => "", "service_until_on" => Date.current.to_s, "unknown_field" => "ignore")
    document = workspaces(:one).sales_documents.new(kind: "order", document_date: Date.current, data: attrs)
    assert_not document.valid?
    assert_includes document.errors.full_messages.join, "Beginn"
  end

  test "Prozente werden auf Cent gerundet" do
    attrs = attributes_for_scope
    attrs["invoice_lines_attributes"]["0"]["unit_price"] = "10,01"
    invoice = OrderInvoicePreparation.new(workspaces(:one), attrs.merge("order_based" => "1", "billing_kind" => "advance", "allocation_mode" => "percent", "allocation_percent" => "33,33")).call
    assert_equal BigDecimal("3.34"), invoice.total
    assert_equal BigDecimal("10.01"), invoice.order_total
  end
end
