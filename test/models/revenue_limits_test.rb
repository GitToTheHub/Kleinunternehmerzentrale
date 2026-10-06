require "test_helper"

class RevenueLimitsTest < ActiveSupport::TestCase
  def workspace_with(amount, on:, mode: "small_business")
    workspace = Workspace.create!
    invoice = workspace.invoices.new(
      issued_on: on, service_on: on, tax_mode: mode, seller_name: "A", seller_street: "B 1", seller_postal_code: "20095",
      seller_city: "Hamburg", seller_country: "DE", seller_tax_identifier: "12/345/67890", buyer_name: "K", buyer_street: "S 2",
      buyer_postal_code: "10115", buyer_city: "Berlin", buyer_country: "DE"
    )
    invoice.invoice_lines.build(description: "x", quantity: 1, unit_price: amount, unit_code: "C62", tax_rate: mode == "standard" ? 19 : 0)
    invoice.save!
    workspace
  end

  def notice_for(workspace, today = Date.new(2026, 10, 6))
    RevenueLimits.new(workspace, today: today).notice
  end

  test "kein Hinweis bei kleinem Umsatz oder ohne Bereich" do
    assert_nil notice_for(nil)
    assert_nil notice_for(workspace_with(5_000, on: Date.new(2026, 3, 1)))
  end

  test "stufenweise Hinweise im laufenden Jahr" do
    assert_equal :info, notice_for(workspace_with(21_000, on: Date.new(2026, 3, 1))).level
    assert_equal :warning, notice_for(workspace_with(26_000, on: Date.new(2026, 3, 1))).level
    assert_equal :alert, notice_for(workspace_with(101_000, on: Date.new(2026, 3, 1))).level
  end

  test "Vorjahr über 25.000 Euro ist ein Hinweis, auch ohne neuen Umsatz" do
    assert_equal :alert, notice_for(workspace_with(26_000, on: Date.new(2025, 6, 1))).level
    assert_nil notice_for(workspace_with(24_000, on: Date.new(2025, 6, 1)))
  end

  test "Regelbesteuerte Rechnungen zählen nicht mit" do
    assert_nil notice_for(workspace_with(50_000, on: Date.new(2026, 3, 1), mode: "standard"))
  end
end
