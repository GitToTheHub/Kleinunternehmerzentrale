require "test_helper"

class StagedInvoiceTest < ActiveSupport::TestCase
  test "Anzahlung Abschlag und Schlussrechnung brauchen keinen Titel fuer die Verknuepfung" do
    advance = build("advance", 300)
    advance.title = nil
    advance.save!
    receive(advance)
    progress = build("progress", 200, root: advance)
    progress.title = ""
    progress.save!
    receive(progress)
    final = build("final", 1000, root: advance)
    final.title = nil
    final.save!
    assert_equal 500, final.deducted_total
    assert_equal 500, final.payment_total
    assert_equal advance.id, final.billing_root_id
  end

  test "Storno ersetzt die Rechnungsart im Originalformat und erhaelt alte Stornonummerierung ohne Platzhalter" do
    advance = build("advance", 400)
    advance.invoice_number_format = "[Jahr]-[Rechnungsart]-[Fortlaufendenummer]"
    advance.save!
    assert_equal "2026-ANZ-0001", advance.invoice_number
    cancellation = advance.build_cancellation
    cancellation.issued_on = Date.new(2026, 10, 31)
    cancellation.save!
    assert_equal "2026-ST-0002", cancellation.invoice_number
    assert_equal advance.invoice_number_format, cancellation.invoice_number_format
    assert_equal "2026-ANZ-0001", advance.reload.invoice_number
    legacy = build("progress", 100)
    legacy.invoice_number_format = "CUSTOM-[Jahr]-[Fortlaufendenummer]"
    legacy.save!
    legacy_cancellation = legacy.build_cancellation
    legacy_cancellation.issued_on = Date.new(2026, 10, 31)
    legacy_cancellation.save!
    assert_equal "ST-2026-0004", legacy_cancellation.invoice_number
    assert_equal "ST-[Jahr]-[Fortlaufendenummer]", legacy_cancellation.invoice_number_format
  end

  test "Schlussrechnung rechnet Zahlungen an und bucht nur den Rest ohne Doppelzaehlung" do
    advance = issue("advance", 300)
    receive(advance)
    progress = issue("progress", 500, root: advance)
    receive(progress)
    final = issue("final", 2000, root: advance, paid: true)
    assert_equal 2000, final.total
    assert_equal 800, final.deducted_total
    assert_equal 1200, final.payment_total
    assert_equal 0, final.amount_due
    assert_equal 1200, final.payment_entry.amount
    assert_equal 2000, advance.workspace.bookkeeping_entries.where(invoice_id: [ advance.id, progress.id, final.id ]).sum(:amount)
    assert_equal [ advance.id, progress.id ], final.deducted_payments.map { |p| p.fetch("invoice_id") }
    assert_equal final.deducted_payments, final.reload.deducted_payments
    assert_not advance.build_cancellation.valid?
    advance.payment_entry.amount = 250
    assert_not advance.payment_entry.save
    assert_not advance.payment_entry.destroy
    refund = advance.payment_entry.refunds.new(advance.payment_entry.refund_attributes.merge(workspace: advance.workspace, paid_on: Date.current, amount: 20, description: "Rückzahlung"))
    assert_not refund.save
    another_final = build("final", 2000, root: advance)
    assert_not another_final.valid?
    assert_match "bereits eine Schlussrechnung", another_final.errors.full_messages.join
    final.build_cancellation.save!
    assert advance.build_cancellation.valid?
  end

  test "unbezahlte und zurueckgezahlte Abschlaege sperren die Schlussrechnung" do
    advance = issue("advance", 300)
    final = build("final", 2000, root: advance)
    assert_not final.valid?
    assert_match "Erfasse zuerst alle Zahlungen", final.errors.full_messages.join
    payment = receive(advance)
    payment.refunds.create!(payment.refund_attributes.merge(workspace: advance.workspace, paid_on: Date.current, amount: 20, description: "Rückzahlung"))
    assert_not final.valid?
  end

  test "Auftragsbezug prueft Workspace Kunde Waehrung und Schlussbetrag" do
    advance = issue("advance", "300,01")
    receive(advance)
    final = build("final", "300,00", root: advance)
    assert_not final.valid?
    assert_equal BigDecimal("-0.01"), final.payment_total
    final.invoice_lines.first.unit_price = "300,01"
    assert final.valid?, final.errors.full_messages.join
    assert_equal 0, final.payment_total
    assert_not final.payment_recordable?
    final.customer = nil
    assert_not final.valid?
    final.customer = advance.customer
    final.workspace = Workspace.create!
    assert_not final.valid?
    assert_match "aus deinem Bereich", final.errors.full_messages.join
    assert_empty final.deducted_payments
    final = build("final", 1000, root: advance)
    final.currency = "USD"
    assert_not final.valid?
    assert_match "nur in Euro", final.errors.full_messages.join
  end

  test "Storno der Schlussrechnung hebt nur den Restbetrag auf" do
    advance = issue("advance", 300)
    receive(advance)
    final = issue("final", 1000, root: advance)
    cancellation = final.build_cancellation
    assert cancellation.valid?, cancellation.errors.full_messages.join
    assert_equal(-1000, cancellation.total)
    assert_equal(-300, cancellation.deducted_total)
    assert_equal(-700, cancellation.payment_total)
    cancellation.save!
    correction = issue("final", 1100, root: advance)
    assert_equal 800, correction.payment_total
  end

  test "XRechnung enthaelt Vorauszahlung und verbleibenden Zahlbetrag" do
    advance = issue("advance", 300)
    receive(advance)
    final = issue("final", 1000, root: advance)
    xml = Nokogiri::XML(XrechnungGenerator.new(final).call)
    value = ->(name) { xml.at_xpath("//*[local-name()='#{name}']").text.to_d }
    assert_equal 1000, value.call("GrandTotalAmount")
    assert_equal 300, value.call("TotalPrepaidAmount")
    assert_equal 700, value.call("DuePayableAmount")
    assert_includes xml.text, advance.invoice_number
    xml = Nokogiri::XML(XrechnungGenerator.new(advance).call)
    assert_equal "386", xml.at_xpath("//*[local-name()='ExchangedDocument']/*[local-name()='TypeCode']").text
  end

  test "Export und Umsatzhinweis beruecksichtigen Auftragsbezug und Restbetrag" do
    advance = issue("advance", 300)
    receive(advance)
    final = issue("final", 1000, root: advance)
    baseline = advance.workspace.invoices.where.not(id: [ advance.id, final.id ]).sum(&:payment_total_in_euros)
    assert_equal baseline + 1000, RevenueLimits.new(advance.workspace).revenue(2026)
    Zip::File.open_buffer(DataExport.new(advance.workspace).call) do |zip|
      rows = CSV.parse(zip.read("rechnungen.csv").force_encoding("UTF-8").delete_prefix("\uFEFF"), col_sep: ";", headers: true)
      row = rows.find { |item| item["Rechnung_ID"] == final.id.to_s }
      assert_equal "final", row["Rechnungsart"]
      assert_equal advance.id.to_s, row["Auftrag_Erstrechnung_ID"]
      assert_equal 700, row["Zahlbetrag"].to_d
      assert_equal advance.id, JSON.parse(row["Angerechnete_Zahlungen_JSON"]).first.fetch("invoice_id")
    end
  end

  test "Workspace Loeschung entfernt auch verknuepfte Rechnungen" do
    advance = issue("advance", 300)
    receive(advance)
    issue("final", 1000, root: advance)
    advance.workspace.erase!
    assert_not Invoice.exists?(advance.id)
  end

  private

  def build(kind, amount, root: nil)
    invoice = Invoice.new(invoices(:one).attributes.except("id", "invoice_number", "created_at", "updated_at"))
    invoice.assign_attributes(billing_kind: kind, billing_root: root, title: "Website Projekt", payment_method: "other", customer: root&.customer)
    invoice.invoice_lines.build(description: "Website", quantity: 1, unit_price: amount, unit_code: "C62")
    invoice
  end

  def issue(kind, amount, root: nil, paid: false)
    invoice = build(kind, amount, root: root)
    invoice.assign_attributes(paid: paid, record_initial_payment: true, received_on: Date.current)
    invoice.save!
    invoice
  end

  def receive(invoice)
    invoice.workspace.bookkeeping_entries.create!(kind: "income", category: "income_small", invoice: invoice,
      paid_on: invoice.issued_on, amount: invoice.payment_total, description: "Zahlung", payment_account: "business")
  end
end
