require "test_helper"

class InvoicePaymentsTest < ActionDispatch::IntegrationTest
  setup do
    post bookkeeping_entries_url, params: { bookkeeping_entry: { kind: "deposit", paid_on: Date.current, amount: 1, description: "Start" } }
    @workspace = BookkeepingEntry.order(:id).last.workspace
    @invoice = build_invoice
  end

  def build_invoice(unit_price: 100, **extra)
    attrs = invoices(:one).attributes.except("id", "workspace_id", "invoice_number", "created_at", "updated_at", "customer_id")
    invoice = @workspace.invoices.new(attrs.merge(issued_on: Date.current, service_on: Date.current, payment_due_on: Date.current + 14).merge(extra))
    invoice.invoice_lines.build(description: "Beratung", quantity: 1, unit_price: unit_price, unit_code: "C62")
    invoice.save!
    invoice
  end

  def payment_params(**extra)
    { kind: "income", category: "income_small", amount: "100", paid_on: Date.current, description: "Zahlung", invoice_id: @invoice.id }.merge(extra)
  end

  def initial_invoice_params
    @invoice.attributes.slice(*Invoice::COPIED_ATTRIBUTES).merge(issued_on: Date.current - 1, service_on: Date.current - 1,
      customer_update_mode: "invoice_only", paid: "1", received_on: Date.current - 1, received_account: "private", title: "Beratung Oktober",
      invoice_lines_attributes: { "0" => { description: "Beratung", quantity: 1, unit_price: "160", unit_code: "C62" } })
  end

  test "payment texts follow the billing kind including the final remaining amount" do
    advance = build_invoice(billing_kind: "advance")
    progress = build_invoice(billing_kind: "progress")
    [ [ @invoice, "Betrag" ], [ advance, "Betrag" ], [ progress, "Betrag" ] ].each do |invoice, amount_label|
      check_payment_texts(invoice, amount_label)
    end
    final = build_invoice(billing_kind: "final", billing_root_id: advance.id, customer_id: advance.customer_id, unit_price: 300)
    assert_equal 200, final.payment_total
    check_payment_texts(final, "Restbetrag")
  end

  def check_payment_texts(invoice, amount_label)
    action = "Rechnung als bezahlt markieren"
    get new_bookkeeping_entry_url(invoice_id: invoice.id)
    assert_response :success
    assert_select "h1", "Rechnung als bezahlt markieren"
    assert_select "button[type=submit]", action
    assert_select ".booking-kind-summary", /#{amount_label}:/
    assert_select ".booking-kind-summary p:first-child", "Rechnungsnummer: #{invoice.invoice_number}"
    assert_select ".booking-kind-summary p:nth-child(2)", "Kunde: #{invoice.buyer_name}"
    assert_select ".cash-payment-choices > legend + small", "Übernimmst du das Geld erst später privat, erfasst du dann eine eigene Privatentnahme."
    get new_bookkeeping_entry_url(invoice_id: invoice.id, payment_popup: "1")
    assert_select "[data-payment-title]", count: 1 do |nodes|
      assert_equal "Rechnung als bezahlt markieren", nodes.first["data-payment-title"]
    end
    post bookkeeping_entries_url, params: { invoice_payment: "1", bookkeeping_entry: { invoice_id: invoice.id, paid_on: Date.current, payment_account: "business" } }
    assert_response :redirect
    assert_equal "#{invoice.billing_label} als bezahlt markiert. Die Einnahme wurde in der Buchhaltung erfasst.", flash[:notice]
    assert_includes invoice.reload.payment_entry.description, "Zahlung zu #{invoice.billing_label}"
  end

  test "paid invoice creates exactly one income with actual payment date account and title" do
    assert_difference [ "Invoice.count", "BookkeepingEntry.count" ], 1 do
      post invoices_url, params: { invoice: initial_invoice_params }
      assert_response :redirect, Nokogiri::HTML(response.body).css(".form-errors").text
    end
    assert_response :redirect
    invoice = Invoice.order(:id).last
    entry = invoice.payment_entry
    assert_equal Date.current - 1, entry.paid_on
    assert_equal 160, entry.amount
    assert_equal "private", entry.payment_account
    assert_includes entry.description, "Beratung Oktober"
    assert_equal 160, BookkeepingReport.new(@workspace.bookkeeping_entries, Date.current.year).income
    get new_bookkeeping_entry_url(invoice_id: invoice.id)
    assert_redirected_to edit_bookkeeping_entry_url(entry)
  end

  test "missing invalid or future payment date cannot create paid invoice or close draft" do
    [ nil, "invalid", Date.current + 1 ].each do |date|
      assert_no_difference [ "Invoice.count", "BookkeepingEntry.count" ] do
        post invoices_url, params: { invoice: initial_invoice_params.merge(received_on: date) }
      end
      assert_response :unprocessable_entity
    end
    assert_no_difference [ "Invoice.count", "BookkeepingEntry.count" ] do
      post invoices_url, params: { invoice: initial_invoice_params.merge(received_account: "unknown") }
    end
    assert_response :unprocessable_entity
  end

  test "foreign paid invoice uses actual euro receipt and unpaid invoice creates no entry" do
    post invoices_url, params: { invoice: initial_invoice_params.merge(currency: "USD", exchange_rate: "0.9", exchange_rate_on: Date.current - 1,
      exchange_rate_source: "manual", received_amount: "142,35") }
    assert_response :redirect, Nokogiri::HTML(response.body).css(".form-errors").text
    assert_equal BigDecimal("142.35"), Invoice.order(:id).last.payment_entry.amount
    assert_no_difference "BookkeepingEntry.count" do
      post invoices_url, params: { invoice: initial_invoice_params.merge(paid: "0", received_on: nil) }
    end
    assert_response :redirect
    assert_nil Invoice.order(:id).last.payment_entry
  end

  test "paid invoice draft preserves payment fields without booking before creation" do
    assert_no_difference [ "Invoice.count", "BookkeepingEntry.count" ] do
      post preview_invoices_url, params: { invoice: initial_invoice_params }
    end
    draft = @workspace.invoice_drafts.active.last
    get edit_draft_invoices_url(draft_id: draft.id)
    assert_select "input[name='invoice[received_on]'][value='#{Date.current - 1}']"
    assert_select "select[name='invoice[received_account]'] option[selected][value='private']"
    post invoices_url, params: { draft_id: draft.id, invoice: initial_invoice_params }
    assert_response :redirect
    assert_equal "completed", draft.reload.status
  end

  test "payment from invoice prepopulates the form and marks it paid without changing the document" do
    snapshot = @invoice.attributes
    get invoice_url(@invoice)
    assert_select "[aria-label='Zahlungsstatus'] h2", "Zahlung ausstehend"
    get new_bookkeeping_entry_url(invoice_id: @invoice.id)
    assert_response :success
    assert_select "input[type='hidden'][name='bookkeeping_entry[invoice_id]'][value='#{@invoice.id}']"
    assert_select "input[name='bookkeeping_entry[amount]']", count: 0
    assert_select "select[name='bookkeeping_entry[category]']", count: 0
    assert_select "main", /100,00/
    assert_difference "BookkeepingEntry.count", 1 do
      post bookkeeping_entries_url, params: { bookkeeping_entry: payment_params(payment_account: "private") }
    end
    assert_response :redirect
    item = @invoice.reload.payment_entry
    assert_equal @workspace, item.workspace
    assert_equal 100, item.amount
    assert_equal snapshot, @invoice.attributes
    assert @invoice.payment_received?
    report = BookkeepingReport.new(@workspace.bookkeeping_entries, Date.current.year)
    assert_equal 100, report.income
    assert_equal 100, report.withdrawals
    get invoice_url(@invoice)
    assert_select "[aria-label='Zahlungsstatus'] h2", "Bezahlt"
    assert_select "a[href='#{edit_bookkeeping_entry_path(item)}']"
    get invoices_url
    assert_select "[data-invoice-id='#{@invoice.id}'] a", "Bezahlt am #{item.paid_on.strftime("%d.%m.%Y")}"
    get bookkeeping_entries_url
    assert_select "a[href='#{invoice_path(@invoice)}']", /Bezahlt/
  end


  test "popup renders errors as HTML and returns the invoice location after saving" do
    get new_bookkeeping_entry_url(invoice_id: @invoice.id, payment_popup: "1")
    assert_response :success
    assert_select "form"
    assert_select "main", count: 0
    attributes = { invoice_id: @invoice.id, paid_on: Date.current + 1, payment_account: "private" }
    post bookkeeping_entries_url, params: { invoice_payment: "1", payment_popup: "1", bookkeeping_entry: attributes }, as: :json
    assert_response :unprocessable_entity
    assert_equal "text/html", response.media_type
    assert_select "[role=alert]"
    post bookkeeping_entries_url, params: { invoice_payment: "1", payment_popup: "1", bookkeeping_entry: attributes.merge(paid_on: Date.current) }, as: :json
    assert_response :success
    assert_equal invoices_path(anchor: "invoice_#{@invoice.id}"), response.parsed_body["location"]
    assert @invoice.reload.payment_received?
  end

  test "short payment form derives invoice details on the server and preserves errors" do
    attributes = { invoice_id: @invoice.id, paid_on: Date.current - 1, payment_account: "private",
      amount: "1", description: "Manipuliert", reference: "Falsch", kind: "expense", category: "expense_other" }
    post bookkeeping_entries_url, params: { invoice_payment: "1", bookkeeping_entry: attributes.merge(paid_on: Date.current + 1) }
    assert_response :unprocessable_entity
    assert_select "h1", "Rechnung als bezahlt markieren"
    assert_select "select[name='bookkeeping_entry[payment_account]'] option[selected][value='private']"
    assert_nil @invoice.reload.payment_entry

    assert_difference "BookkeepingEntry.count", 1 do
      post bookkeeping_entries_url, params: { invoice_payment: "1", bookkeeping_entry: attributes }
    end
    assert_redirected_to invoices_url(anchor: "invoice_#{@invoice.id}")
    follow_redirect!
    assert_select "#invoice_#{@invoice.id}", /Bezahlt/
    payment = @invoice.reload.payment_entry
    assert_equal 100, payment.amount
    assert_equal @invoice.payment_description, payment.description
    assert_equal @invoice.invoice_number, payment.reference
    assert_equal "income_small", payment.category
    assert_equal Date.current - 1, payment.paid_on
    assert_equal "private", payment.payment_account
    assert_no_difference "BookkeepingEntry.count" do
      post bookkeeping_entries_url, params: { invoice_payment: "1", bookkeeping_entry: attributes }
    end
    assert_response :unprocessable_entity
  end

  test "cash payment allocation survives popup errors editing export and deletion" do
    attributes = { invoice_id: @invoice.id, paid_on: Date.current, payment_account: "cash", cash_usage: "split", cash_private_amount: "100,01" }
    post bookkeeping_entries_url, params: { invoice_payment: "1", payment_popup: "1", bookkeeping_entry: attributes }, as: :json
    assert_response :unprocessable_entity
    assert_select "select[name='bookkeeping_entry[payment_account]'] option[selected][value='cash']"
    assert_select "input[name='bookkeeping_entry[cash_usage]'][value='split'][checked]"
    assert_nil @invoice.reload.payment_entry
    post bookkeeping_entries_url, params: { invoice_payment: "1", payment_popup: "1", bookkeeping_entry: attributes.merge(cash_private_amount: "33,34") }, as: :json
    assert_response :success
    payment = @invoice.reload.payment_entry
    assert_equal BigDecimal("33.34"), payment.cash_private_amount
    assert_equal 100, payment.amount
    snapshot = @invoice.attributes
    get edit_bookkeeping_entry_url(payment)
    assert_select "label", "Zahlungsart"
    assert_select "input[name='bookkeeping_entry[cash_usage]'][value='split'][checked]"
    assert_select "input[name='bookkeeping_entry[cash_private_amount]'][value='33,34']"
    patch bookkeeping_entry_url(payment), params: { bookkeeping_entry: { cash_usage: "private" } }
    assert_response :redirect
    assert_equal 100, payment.reload.cash_private_amount
    assert_equal snapshot, @invoice.reload.attributes
    Zip::File.open_buffer(DataExport.new(@workspace).call) do |zip|
      rows = CSV.parse(zip.read("buchhaltung.csv").force_encoding("UTF-8").delete_prefix("\uFEFF"), headers: true, col_sep: ";")
      row = rows.find { |item| item["Rechnung_ID"] == @invoice.id.to_s }
      assert_equal "cash", row["Konto"]
      assert_equal "private", row["Bargeldverwendung"]
      assert_equal 100, row["Bargeld_privat_EUR"].to_d
    end
    delete bookkeeping_entry_url(payment)
    assert_response :see_other
    assert_not @invoice.reload.payment_received?
    assert_equal 0, BookkeepingReport.new(@workspace.bookkeeping_entries, Date.current.year).withdrawals
  end

  test "cash refunds use the actual private funding and preserve the original payment" do
    post bookkeeping_entries_url, params: { invoice_payment: "1", bookkeeping_entry: { invoice_id: @invoice.id, paid_on: Date.current, payment_account: "cash", cash_usage: "split", cash_private_amount: "33,34" } }
    assert_response :redirect
    payment = @invoice.reload.payment_entry
    get refund_bookkeeping_entry_url(payment)
    assert_response :success
    assert_select "legend", "Woher stammt das Bargeld für die Rückzahlung?"
    post create_refund_bookkeeping_entry_url(payment), params: { bookkeeping_entry: { paid_on: Date.current, amount: "25,02", description: "Rückzahlung", payment_account: "cash", cash_usage: "split", cash_private_amount: "10,01" } }
    assert_response :redirect
    refund = payment.refunds.sole
    assert_equal BigDecimal("10.01"), refund.cash_private_amount
    assert_equal BigDecimal("33.34"), payment.reload.cash_private_amount
    report = BookkeepingReport.new(@workspace.bookkeeping_entries, Date.current.year)
    assert_equal BigDecimal("74.98"), report.income
    assert_equal BigDecimal("23.33"), report.withdrawals
    get edit_bookkeeping_entry_url(refund)
    assert_select "input[name='bookkeeping_entry[cash_private_amount]'][value='10,01']"
    patch bookkeeping_entry_url(refund), params: { bookkeeping_entry: { cash_usage: "business" } }
    assert_response :redirect
    assert_equal 0, refund.reload.cash_private_amount
    assert_equal BigDecimal("33.34"), BookkeepingReport.new(@workspace.bookkeeping_entries, Date.current.year).withdrawals
  end

  test "short payment form rejects invoices from another workspace" do
    assert_no_difference "BookkeepingEntry.count" do
      post bookkeeping_entries_url, params: { invoice_payment: "1", bookkeeping_entry: { invoice_id: invoices(:one).id, paid_on: Date.current, payment_account: "business" } }
    end
    assert_response :not_found
  end

  test "short foreign payment form keeps the actual Euro amount editable" do
    @invoice = build_invoice(currency: "USD", exchange_rate: "0.9", exchange_rate_on: Date.current, exchange_rate_source: "Testkurs")
    get new_bookkeeping_entry_url(invoice_id: @invoice.id)
    assert_select "input[name='bookkeeping_entry[amount]'][value='90,00']"
    post bookkeeping_entries_url, params: { invoice_payment: "1", bookkeeping_entry: { invoice_id: @invoice.id, paid_on: Date.current, payment_account: "business", amount: "92,00" } }
    assert_response :redirect
    assert_equal 92, @invoice.reload.payment_entry.amount
  end

  test "existing EÜR income can be linked and editing or deleting it updates the payment" do
    post bookkeeping_entries_url, params: { bookkeeping_entry: payment_params(invoice_id: nil) }
    item = BookkeepingEntry.order(:id).last
    assert_not @invoice.reload.payment_received?
    patch bookkeeping_entry_url(item), params: { bookkeeping_entry: { invoice_id: @invoice.id } }
    assert_response :redirect
    assert @invoice.reload.payment_received?
    patch bookkeeping_entry_url(item), params: { bookkeeping_entry: { paid_on: Date.current - 1 } }
    assert_equal Date.current - 1, @invoice.reload.payment_entry.paid_on
    delete bookkeeping_entry_url(item)
    assert_response :see_other
    assert_not @invoice.reload.payment_received?
  end

  test "duplicate payments are rejected and the payment action opens the existing entry" do
    post bookkeeping_entries_url, params: { bookkeeping_entry: payment_params }
    item = @invoice.reload.payment_entry
    assert_no_difference "BookkeepingEntry.count" do
      post bookkeeping_entries_url, params: { bookkeeping_entry: payment_params }
    end
    assert_response :unprocessable_entity
    get new_bookkeeping_entry_url(invoice_id: @invoice.id)
    assert_redirected_to edit_bookkeeping_entry_url(item)
    assert_equal 100, BookkeepingReport.new(@workspace.bookkeeping_entries, Date.current.year).income
  end

  test "foreign workspace invoices cannot be viewed or linked through the EÜR" do
    other = invoices(:one)
    get new_bookkeeping_entry_url(invoice_id: other.id)
    assert_response :not_found
    assert_no_difference "BookkeepingEntry.count" do
      post bookkeeping_entries_url, params: { bookkeeping_entry: payment_params(invoice_id: other.id) }
    end
    assert_response :unprocessable_entity
    assert_nil other.reload.payment_entry
  end

  test "only complete real income payments can settle a Euro invoice" do
    [ { amount: 50 }, { paid_on: Date.current + 1 }, { kind: "expense", category: "expense_other" }, { reversal: true }, { category: "vat_refund" } ].each do |invalid|
      assert_no_difference "BookkeepingEntry.count" do
        post bookkeeping_entries_url, params: { bookkeeping_entry: payment_params(**invalid) }
      end
      assert_response :unprocessable_entity
      assert_not @invoice.reload.payment_received?
    end
  end

  test "foreign invoices use the entered actual Euro amount rather than the invoice rate" do
    @invoice = build_invoice(currency: "USD", exchange_rate: "0.9", exchange_rate_on: Date.current, exchange_rate_source: "Testkurs")
    post bookkeeping_entries_url, params: { bookkeeping_entry: payment_params(amount: "92,00") }
    assert_response :redirect
    assert_equal 92, @invoice.reload.payment_entry.amount
    assert @invoice.payment_received?
  end

  test "cancellation cannot be settled and existing payment survives cancellation and workspace erasure" do
    post bookkeeping_entries_url, params: { bookkeeping_entry: payment_params }
    payment = @invoice.reload.payment_entry
    cancellation = @invoice.build_cancellation
    cancellation.save!
    get edit_bookkeeping_entry_url(payment)
    assert_select "select[name='bookkeeping_entry[invoice_id]'] option[selected][value='#{@invoice.id}']"
    assert_no_difference "BookkeepingEntry.count" do
      post bookkeeping_entries_url, params: { bookkeeping_entry: payment_params(invoice_id: cancellation.id) }
    end
    assert_response :unprocessable_entity
    assert_equal "Storniert", @invoice.reload.payment_status
    assert_equal 100, BookkeepingReport.new(@workspace.bookkeeping_entries, Date.current.year).income
    @workspace.erase!
    assert_not BookkeepingEntry.exists?(payment.id)
    assert_not Invoice.exists?(@invoice.id)
  end
end
