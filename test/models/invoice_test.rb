require "test_helper"

class InvoiceTest < ActiveSupport::TestCase
  test "unterschiedliche Stundensaetze behalten die Kundenvorgabe" do
    customer = Customer.new(hourly_rate: 60)
    invoice = Invoice.new(currency: "EUR")
    invoice.invoice_lines.build(unit_code: "HUR", unit_price: 80)
    invoice.invoice_lines.build(unit_code: "HUR", unit_price: 100)
    assert_nil invoice.uniform_hourly_rate
    assert_equal 60, customer.attributes_from_invoice(invoice)[:hourly_rate]
    invoice.invoice_lines.last.unit_price = 80
    assert_equal 80, invoice.uniform_hourly_rate
    assert_equal 80, customer.attributes_from_invoice(invoice)[:hourly_rate]
    invoice.invoice_lines.last.mark_for_destruction
    assert_equal 80, invoice.uniform_hourly_rate
  end

  test "ein aktivierter Leistungszeitraum verlangt ein Enddatum auch ohne Browservalidierung" do
    invoice = Invoice.new(invoices(:one).attributes.except("id", "invoice_number", "created_at", "updated_at"))
    invoice.invoice_lines.build(description: "Beratung", quantity: 1, unit_price: 50, unit_code: "C62")
    invoice.service_period = true
    assert_not invoice.valid?
    assert invoice.errors.added?(:service_until_on, :blank)
  end

  test "ein einzelner Leistungstag braucht kein Bis-Datum und alte Rechnungen bleiben stornierbar" do
    invoice = Invoice.new(invoices(:one).attributes.except("id", "invoice_number", "created_at", "updated_at"))
    invoice.invoice_lines.build(description: "Beratung", quantity: 1, unit_price: 50, unit_code: "C62")
    invoice.service_on = Date.new(2026, 11, 1)
    invoice.service_until_on = invoice.service_on
    assert_not invoice.valid?
    assert_match "Für einen einzelnen Tag", invoice.errors[:service_until_on].join
    invoice.service_until_on = nil
    assert invoice.valid?, invoice.errors.full_messages.join
    invoice.service_until_on = invoice.service_on + 1
    invoice.save!
    Invoice.where(id: invoice.id).update_all(service_until_on: invoice.service_on)
    invoice.reload
    cancellation = invoice.build_cancellation
    assert cancellation.valid?, cancellation.errors.full_messages.join
    assert_equal invoice.service_on, cancellation.service_until_on
  end

  test "Summen runden erst jede Position und dann die Steuer je Steuersatz" do
    invoice = Invoice.new(tax_mode: "standard")
    2.times { invoice.invoice_lines.build(quantity: "0.5", unit_price: "0.01", tax_rate: 19) }
    invoice.invoice_lines.build(quantity: 1, unit_price: 10, tax_rate: 7)
    assert_equal BigDecimal("10.02"), invoice.net_total
    assert_equal BigDecimal("0.70"), invoice.tax_total
    assert_equal BigDecimal("10.72"), invoice.total
  end
end
