require "test_helper"

class InvoiceCurrencyTest < ActiveSupport::TestCase
  def invoice_in(currency, **attributes)
    invoice = Invoice.new(invoices(:one).attributes.except("id", "invoice_number", "created_at", "updated_at").merge(
      workspace: Workspace.create!, currency: currency, issued_on: Date.new(2026, 10, 11),
      exchange_rate: "0.92", exchange_rate_on: Date.new(2026, 10, 11), exchange_rate_source: "Bankabrechnung"
    ).merge(attributes))
    invoice.invoice_lines.build(description: "Beratung", quantity: 1, unit_price: "100.01", unit_code: "C62")
    invoice
  end

  test "Fremdwaehrung wird genau in Euro umgerechnet und Storno verwendet denselben Kurs" do
    invoice = invoice_in("USD")
    invoice.save!
    assert_equal BigDecimal("100.01"), invoice.total
    assert_equal BigDecimal("92.01"), invoice.total_in_euros
    limits = RevenueLimits.new(invoice.workspace, today: invoice.issued_on)
    assert_equal BigDecimal("92.01"), limits.current_revenue
    cancellation = invoice.build_cancellation
    cancellation.save!
    assert_equal "USD", cancellation.currency
    assert_equal invoice.exchange_rate, cancellation.exchange_rate
    assert_equal invoice.exchange_rate_on, cancellation.exchange_rate_on
    assert_equal invoice.exchange_rate_source, cancellation.exchange_rate_source
    assert_equal BigDecimal("-92.01"), cancellation.total_in_euros
    assert_equal 0, RevenueLimits.new(invoice.workspace).revenue(2026)
  end

  test "sichtbarer Kurs ist Fremdwaehrung pro Euro und wird intern umgerechnet" do
    invoice = invoice_in("USD", exchange_rate_quote: "1.25")
    assert_equal BigDecimal("1.25"), invoice.exchange_rate_quote
    assert_equal BigDecimal("0.8"), invoice.exchange_rate
    assert_equal BigDecimal("80.01"), invoice.total_in_euros
    invoice.save!
    assert_equal BigDecimal("1.25"), invoice.reload.exchange_rate_quote
    invoice.exchange_rate_quote = "0"
    assert_not invoice.valid?
  end

  test "Kurs Datum und Quelle sind fuer Fremdwaehrungen erforderlich" do
    [ nil, "", "0", "-1", "abc", "1000000000" ].each do |rate|
      invoice = invoice_in("CHF", exchange_rate: rate)
      assert_not invoice.valid?
      assert invoice.errors[:exchange_rate].any?
    end
    invoice = invoice_in("GBP", exchange_rate_on: nil, exchange_rate_source: " ")
    assert_not invoice.valid?
    assert invoice.errors[:exchange_rate_on].any?
    assert invoice.errors[:exchange_rate_source].any?
    assert_not invoice_in("INVALID").valid?
  end

  test "Euro bleibt Standard und hat keinen Umrechnungskurs" do
    assert_equal "EUR", Invoice.new.currency
    invoice = invoice_in("EUR")
    assert invoice.valid?, invoice.errors.full_messages.join(", ")
    assert_nil invoice.exchange_rate
    assert_nil invoice.exchange_rate_on
    assert_nil invoice.exchange_rate_source
    assert_equal invoice.total, invoice.total_in_euros
  end

  test "Fremdwaehrung ueberschreibt keinen gespeicherten Euro Stundensatz" do
    invoice = invoice_in("USD")
    invoice.invoice_lines.first.unit_code = "HUR"
    profile = invoice.workspace.create_business_profile!(hourly_rate: 80)
    invoice.save!
    assert_equal 80, profile.reload.hourly_rate
    assert_nil invoice.customer.hourly_rate
  end
end
