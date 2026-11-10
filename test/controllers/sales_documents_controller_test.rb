require "test_helper"

class SalesDocumentsControllerTest < ActionDispatch::IntegrationTest
  def scope_params
    invoices(:one).attributes.slice(*Invoice::COPIED_ATTRIBUTES).merge(
      "issued_on" => Date.current.to_s, "service_on" => Date.current.to_s, "customer_id" => nil,
      "invoice_lines_attributes" => { "0" => { "description" => "Vereinbarte Anpassungen", "quantity" => "1", "unit_price" => "800,00", "unit_code" => "LS", "tax_rate" => "0" } })
  end

  test "direkte Anzahlungen werden ausgewaehlt im Entwurf gespeichert und als Schlussrechnung exportiert" do
    ids = []
    [ 300, 100 ].each do |amount|
      input = scope_params.merge("billing_kind" => "advance", "allocation_basis" => "direct", "paid" => "1", "received_on" => Date.current)
      input["invoice_lines_attributes"]["0"]["unit_price"] = amount.to_s
      assert_no_difference "SalesDocument.count" do
        post invoices_url, params: { invoice: input }
        assert_response :redirect
      end
      ids << Invoice.order(:id).last.id
    end
    source = Invoice.find(ids.first)
    get new_invoice_url(billing_kind: "final")
    assert_response :success
    assert_select "input[name='invoice[settlement_invoice_ids][]']", count: 2
    input = scope_params.merge("billing_kind" => "final", "customer_id" => source.customer_id, "customer_update_mode" => "invoice_only", "settlement_invoice_ids" => ids.map(&:to_s))
    patch draft_invoices_url, params: { invoice: input }, as: :json
    assert_response :success
    draft = InvoiceDraft.order(:id).last
    assert_equal ids.map(&:to_s), draft.data["settlement_invoice_ids"]
    post invoices_url, params: { invoice: input, draft_id: draft.id }
    assert_response :redirect
    final = Invoice.order(:id).last
    assert_equal 400.to_d, final.payment_total
    get export_url
    Zip::File.open_buffer(response.body) do |zip|
      exported = JSON.parse(zip.read("rechnungs-auftragsbezug.json")).find { |entry| entry["invoice_id"] == final.id }
      assert_equal ids, exported["order_snapshot"]["settlement_invoice_ids"]
    end
    get invoice_url(source)
    assert_select "a[href='#{invoice_path(final)}']", text: /Schlussrechnung/
    assert_no_difference "Invoice.count" do
      post invoices_url, params: { invoice: input }
      assert_response :unprocessable_entity
    end
  end

  test "Korrektur einer Gesamtanzahlung kann auf Positionsanteile wechseln" do
    post invoices_url, params: { invoice: scope_params.merge("order_based" => "1", "billing_kind" => "advance", "allocation_mode" => "percent", "allocation_percent" => "50") }
    assert_response :redirect
    invoice = Invoice.order(:id).last
    invoice.build_cancellation.save!
    get new_invoice_url(copy_from: invoice.id)
    assert_response :success
    assert_select "[data-order-billing-target=panel]" do |nodes|
      values = JSON.parse(nodes.first["data-initial-values"])
      assert_equal "amount", values["0"]["mode"]
      assert_equal 400.to_d, values["0"]["value"].to_d
    end
  end

  test "Positionsanteile bleiben im Entwurf erhalten und die Schlussrechnung zieht nur erhaltene Zahlungen ab" do
    attrs = scope_params.merge("allocation_basis" => "positions", "order_based" => "1", "billing_kind" => "advance",
      "position_allocations" => { "0" => { "mode" => "percent", "value" => "50" }, "1" => { "mode" => "amount", "value" => "125,00" } },
      "invoice_lines_attributes" => {
        "0" => { "description" => "Material", "quantity" => "1", "unit_price" => "300", "unit_code" => "LS", "tax_rate" => "0" },
        "1" => { "description" => "Umsetzung", "quantity" => "1", "unit_price" => "500", "unit_code" => "LS", "tax_rate" => "0" }
      })
    attrs["invoice_lines_attributes"] = { "17" => attrs["invoice_lines_attributes"]["0"], "42" => attrs["invoice_lines_attributes"]["1"] }
    attrs["position_allocations"] = { "17" => attrs["position_allocations"]["0"], "42" => attrs["position_allocations"]["1"] }
    patch draft_invoices_url, params: { invoice: attrs }, as: :json
    assert_response :success
    draft = InvoiceDraft.order(:id).last
    assert_equal "positions", draft.data["allocation_basis"]
    assert_equal "125,00", draft.data["position_allocations"]["42"]["value"]
    get edit_draft_invoices_url(draft_id: draft.id)
    assert_response :success
    assert_select "[data-order-billing-target=panel]" do |nodes|
      initial = JSON.parse(nodes.first["data-initial-values"])
      assert_equal "50", initial["0"]["value"]
      assert_equal "125,00", initial["1"]["value"]
    end
    post invoices_url, params: { draft_id: draft.id, invoice: attrs.merge("paid" => "1", "received_on" => Date.current) }
    assert_response :redirect
    invoice = Invoice.order(:id).last
    assert_equal "positions", invoice.allocation_mode
    assert_equal 275.to_d, invoice.total
    assert_equal 275.to_d, invoice.payment_entry.amount
    assert_equal 800.to_d, invoice.sales_document.total_amount
    get export_url
    Zip::File.open_buffer(response.body) do |zip|
      exported = JSON.parse(zip.read("rechnungs-auftragsbezug.json")).find { |entry| entry["invoice_id"] == invoice.id }
      assert_equal [ "150.0", "125.0" ], exported["order_snapshot"]["allocations"].map { |entry| entry["amount"] }
    end
    post invoices_url, params: { invoice: scope_params.merge("billing_kind" => "final", "sales_document_id" => invoice.sales_document_id, "customer_id" => invoice.customer_id, "customer_update_mode" => "invoice_only") }
    assert_response :redirect
    final = Invoice.order(:id).last
    assert_equal 800.to_d, final.total
    assert_equal 275.to_d, final.deducted_total
    assert_equal 525.to_d, final.payment_total
  end

  test "Nummernvorschau nutzt den Dokumenttyp und reserviert keine Nummer" do
    %w[offer order].each do |kind|
      assert_no_difference "SalesDocument.count" do
        get next_number_sales_documents_url, params: { billing_kind: kind, issued_on: Date.current.iso8601, invoice_number_format: "[Rechnungsart]-[Jahr]-[Fortlaufendenummer]", invoice_number_last: "99" }
        assert_response :success
        assert_equal "#{InvoiceNumber::TYPE_CODES.fetch(kind)}-#{Date.current.year}-0100", response.parsed_body["invoice_number"]
      end
    end
    get next_number_sales_documents_url, params: { billing_kind: "offer", issued_on: Date.current.iso8601, invoice_number_format: "[Kundenkürzel]-[Fortlaufendenummer]" }
    assert_response :unprocessable_entity
    assert_equal "buyer_abbreviation", response.parsed_body["field"]
  end

  test "Auftrag kann ein vorhandenes Angebot ohne erneute Formulareingabe uebernehmen" do
    post sales_documents_url, params: { kind: "offer", document_date: Date.current, invoice: scope_params }
    offer = SalesDocument.order(:id).last
    get new_sales_document_url(kind: "order")
    assert_select "select#source_offer_id option[value='#{offer.id}']", text: /#{offer.document_number}/
    assert_difference "SalesDocument.count", 1 do
      post sales_documents_url, params: { kind: "order", source_offer_id: offer.id }
    end
    order = offer.reload.accepted_order
    assert_redirected_to sales_document_url(order)
    assert_equal offer.data, order.data
    assert_no_difference "SalesDocument.count" do
      post sales_documents_url, params: { kind: "order", source_offer_id: offer.id }
    end
    get new_sales_document_url(kind: "order")
    assert_select "select#source_offer_id", count: 0
    other = open_session
    other.post sales_documents_url, params: { kind: "order", source_offer_id: offer.id }
    assert_equal 404, other.response.status
    assert_no_difference "SalesDocument.count" do
      post sales_documents_url, params: { kind: "order", source_offer_id: order.id }
      assert_response :not_found
    end
  end

  test "gemeinsames Formular zeigt passende Datumsfelder und verwendet das Dokumentdatum" do
    %w[offer order].each do |kind|
      get new_sales_document_url(kind: kind)
      assert_response :success
      assert_select ".invoice-step", count: 4
      assert_select "form[data-controller~='customer-select']"
      assert_select "input[name='invoice[seller_hourly_rate]']"
      assert_select "input[name='invoice[paid]']", count: 0
    end
    date = Date.current - 3.days
    post sales_documents_url, params: { kind: "offer", invoice: scope_params.merge("issued_on" => date.to_s) }
    offer = SalesDocument.order(:id).last
    assert_redirected_to sales_document_url(offer)
    assert_equal date, offer.document_date
    get edit_sales_document_url(offer)
    assert_select "input#invoice_issued_on[value='#{date.iso8601}']"
  end

  test "Angebot Auftrag und Rechnungslinks sind workspace isoliert" do
    get sales_documents_url
    assert_response :success
    assert_no_difference "Invoice.count" do
      post sales_documents_url, params: { kind: "offer", document_date: Date.current, invoice: scope_params }
    end
    offer = SalesDocument.order(:id).last
    assert_redirected_to sales_document_url(offer)
    assert_equal 800.to_d, offer.total_amount
    patch sales_document_url(offer), params: { lock_version: offer.lock_version, document_date: Date.current, invoice: scope_params.merge("title" => "Neuer Titel") }
    assert_redirected_to sales_document_url(offer)
    post accept_sales_document_url(offer)
    order = offer.reload.accepted_order
    assert_redirected_to sales_document_url(order)
    assert_no_difference "SalesDocument.count" do
      post accept_sales_document_url(offer)
    end
    assert_equal "Neuer Titel", order.title
    other = open_session
    other.get sales_document_url(order)
    assert_equal 404, other.response.status
    other.get new_invoice_url(sales_document_id: order.id)
    assert_equal 404, other.response.status
    get export_url
    Zip::File.open_buffer(response.body) do |zip|
      assert_includes zip.read("angebote-und-auftraege.json"), order.document_number
    end
  end

  test "Entwurfsuebersicht berechnet Anzahlungen aus dem Gesamtauftrag ohne eigene Positionen" do
    post invoices_url, params: { invoice: scope_params.merge("order_based" => "1", "billing_kind" => "advance", "allocation_mode" => "percent", "allocation_percent" => "50", "paid" => "1", "received_on" => Date.current) }
    assert_response :redirect
    order = Invoice.last.sales_document
    input = scope_params.except("invoice_lines_attributes").merge("sales_document_id" => order.id, "billing_kind" => "advance", "allocation_mode" => "percent", "allocation_percent" => "50")
    patch draft_invoices_url, params: { invoice: input }, as: :json
    assert_response :success
    assert_no_difference [ "Invoice.count", "SalesDocument.count", "BookkeepingEntry.count" ] do
      get invoices_url
      assert_response :success
      assert_select ".invoice-draft-card__amount strong", text: "400,00 € von 800,00 €"
      assert_select ".invoice-draft-card .invoice-list__order-payment", text: "Bisher bezahlt: 400,00 € (#{Invoice.last.invoice_number})"
      assert_select ".invoice-draft-card .invoice-list__current-payment", text: "Diese weitere Anzahlung: 400,00 €"
    end
    post invoices_url, params: { invoice: input.merge("customer_id" => Invoice.last.customer_id, "customer_update_mode" => "invoice_only", "paid" => "1", "received_on" => Date.current) }
    assert_response :redirect
    get invoices_url
    assert_select "#invoice_#{Invoice.last.id} .invoice-list__order-payment", text: "Gesamtauftrag vollständig bezahlt: 800,00 €."
  end

  test "server berechnet Anzahlung und Rest und verhindert doppelte Vollabrechnung" do
    attrs = scope_params.merge("order_based" => "1", "billing_kind" => "advance", "allocation_mode" => "percent", "allocation_percent" => "50", "paid" => "1", "received_on" => Date.current)
    post invoices_url, params: { invoice: attrs }
    assert_response :redirect
    advance = Invoice.order(:id).last
    order = advance.sales_document
    assert_equal 400.to_d, advance.total
    assert_equal 400.to_d, advance.payment_entry.amount
    assert_equal 800.to_d, order.total_amount
    get invoice_url(advance)
    assert_response :success
    %w[advance progress].zip([ "Weitere Anzahlung erstellen", "Abschlagsrechnung erstellen" ]).each do |kind, label|
      path = new_invoice_path(sales_document_id: order.id, billing_kind: kind)
      get invoice_url(advance)
      assert_select "a[href=?]", path, text: label
      get path
      assert_response :success
      assert_select "h1", text: "#{Invoice::BILLING_KINDS.fetch(kind)} erstellen"
      assert_select "[data-billing-kind-target=description]", text: InvoicesHelper::INVOICE_FORM_HINTS.fetch(kind)
      assert_select "input[name='invoice[billing_kind]'][value=?][checked]", kind
      assert_select "input[name='invoice[sales_document_id]'][value=?]", order.id.to_s
    end
    tampered = scope_params.merge("sales_document_id" => order.id, "customer_id" => advance.customer_id, "customer_update_mode" => "invoice_only", "billing_kind" => "progress", "allocation_mode" => "percent", "allocation_percent" => "80")
    assert_no_difference "Invoice.count" do
      post invoices_url, params: { invoice: tampered }
      assert_response :unprocessable_entity
    end
    assert_no_difference "Invoice.count" do
      post invoices_url, params: { invoice: tampered.merge("billing_kind" => "regular") }
      assert_response :unprocessable_entity
    end
    post invoices_url, params: { invoice: tampered.merge("billing_kind" => "final") }
    assert_response :redirect
    final = Invoice.order(:id).last
    assert_equal 800.to_d, final.total
    assert_equal 400.to_d, final.payment_total
    assert_equal 400.to_d, final.deducted_total
    xml = Nokogiri::XML(XrechnungGenerator.new(final).call)
    assert_equal 400.to_d, xml.xpath("//*[local-name()='DuePayableAmount']").text.to_d
    assert order.reload.closed?
  end

  test "Validierungsfehler erhalten den vollen Auftrag statt den Anzahlungsbetrag erneut zu halbieren" do
    attrs = scope_params.merge("order_based" => "1", "billing_kind" => "advance", "allocation_mode" => "percent", "allocation_percent" => "50", "seller_name" => "")
    assert_no_difference "SalesDocument.count" do
      post invoices_url, params: { invoice: attrs }
      assert_response :unprocessable_entity
    end
    assert_select "input[name='invoice[invoice_lines_attributes][0][unit_price]'][value='800,00']"
    assert_select "input[name='invoice[invoice_lines_attributes][0][description]'][value='Vereinbarte Anpassungen']"
    post invoices_url, params: { invoice: attrs.merge("seller_name" => "Teststudio") }
    assert_response :redirect
    assert_equal 400.to_d, Invoice.order(:id).last.total
  end

  test "unbezahlte Anzahlung verhindert Schlussrechnung und Workspace Loeschung nimmt Auftraege mit" do
    post invoices_url, params: { invoice: scope_params.merge("order_based" => "1", "billing_kind" => "advance", "allocation_mode" => "amount", "allocation_amount" => "400,00") }
    invoice = Invoice.order(:id).last
    assert_no_difference "Invoice.count" do
      post invoices_url, params: { invoice: scope_params.merge("billing_kind" => "final", "sales_document_id" => invoice.sales_document_id, "customer_id" => invoice.customer_id, "customer_update_mode" => "invoice_only") }
      assert_response :unprocessable_entity
    end
    workspace = invoice.workspace
    document_ids = workspace.sales_documents.pluck(:id)
    workspace.erase!
    assert_empty SalesDocument.where(id: document_ids)
  end
end
