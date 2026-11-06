require "test_helper"
require Rails.root.join("db/migrate/20261008200000_rename_invoice_sequence_placeholder")

class InvoiceNumberTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:one)
    @date = Date.new(2026, 10, 8)
  end

  test "neue Kuerzel lassen historische Rechnungsnummern unveraendert" do
    historical = invoices(:one)
    Invoice.where(id: historical.id).update_all(invoice_number: "AZ-2026-0041", issued_on: @date, invoice_number_sequence: 41)
    assert_equal "ANZ-2026-0042", InvoiceNumber.new(@workspace.invoices, date: @date, billing_kind: "advance").next_number
    assert_equal "ABS-2026-0042", InvoiceNumber.new(@workspace.invoices, date: @date, billing_kind: "progress").next_number
    assert_equal "AZ-2026-0041", historical.reload.invoice_number
  end

  test "Rechnungsart ersetzt Platzhalter ohne eigene Jahreszaehler zu beginnen" do
    Invoice.where(id: invoices(:one).id).update_all(issued_on: @date, invoice_number_sequence: 41)
    InvoiceNumber::TYPE_CODES.each do |kind, code|
      assert_equal [ "2026-#{code}-0042", 42, nil ], InvoiceNumber.new(@workspace.invoices, date: @date,
        format: "[Jahr]-[Rechnungsart]-[Fortlaufendenummer]", billing_kind: kind).number_and_sequence
      assert_equal "ST-2026-0042", InvoiceNumber.new(@workspace.invoices, date: @date,
        billing_kind: kind, cancellation: true).next_number
    end
    assert_equal "RE-2026-0042", InvoiceNumber.new(@workspace.invoices, date: @date,
      format: "RE-[Jahr]-[Fortlaufendenummer]", billing_kind: "advance").next_number
    error = assert_raises(InvoiceNumber::Invalid) { InvoiceNumber.new(@workspace.invoices, date: @date, billing_kind: "unknown") }
    assert_equal :billing_kind, error.field
  end

  test "alter Rechnungstyp Platzhalter bleibt unterstuetzt" do
    assert_equal "ANZ-2026-0001", InvoiceNumber.new(@workspace.invoices, date: @date,
      format: "[Rechnungstyp]-[Jahr]-[Fortlaufendenummer]", billing_kind: "advance").next_number
  end

  test "Datum und Kundenkuerzel funktionieren ohne lueckenlose Nummern" do
    assert_equal "BEG-2026-10-08", number("[Kundenkürzel]-[Jahr]-[Monat]-[Tag]", "beg")
    Invoice.where(id: invoices(:one).id).update_all(invoice_number: "BEG-2026-10-08")
    assert_equal "BEG-2026-10-08-02", number("[Kundenkürzel]-[Jahr]-[Monat]-[Tag]", "beg")
    assert_equal "AND-2026-10-08", number("[Kundenkürzel]-[Jahr]-[Monat]-[Tag]", "AND")
  end

  test "Zaehler setzt bestehende Nummern fort und reserviert bei Vorschauen nichts" do
    Invoice.where(id: invoices(:one).id).update_all(invoice_number: "RE-2026-0099")
    2.times { assert_equal "BEG-2026-10-08-0100", number("[Kundenkürzel]-[Jahr]-[Monat]-[Tag]-[Fortlaufendenummer]", "BEG") }
    Invoice.where(id: invoices(:two).id).update_all(invoice_number: "AND-2026-0105", invoice_number_sequence: 105)
    assert_equal "BEG-2026-0106", number("[Kundenkürzel]-[Jahr]-[Fortlaufendenummer]", "BEG")
  end

  test "jahreslose Nummern bleiben auch beim Jahreswechsel eindeutig" do
    Invoice.where(id: invoices(:one).id).update_all(invoice_number: "X-0001", issued_on: Date.new(2025, 12, 31), invoice_number_sequence: 1)
    assert_equal "X-0001-02", number("X-[Fortlaufendenummer]")
    assert_equal "X-0002", InvoiceNumber.new(@workspace.invoices, date: @date, format: "X-[Fortlaufendenummer]", sequence_start: "2").next_number
    assert_equal "X-0001", InvoiceNumber.new(Invoice.none, date: @date, format: "X-[Fortlaufendenummer]").next_number
  end

  test "automatischer Zusatz ueberspringt belegte Nummern ohne sie zu veraendern" do
    Invoice.where(id: invoices(:one).id).update_all(invoice_number: "BEG-2026-10-08")
    Invoice.where(id: invoices(:two).id).update_all(invoice_number: "BEG-2026-10-08-02")
    2.times { assert_equal "BEG-2026-10-08-03", number("[Kundenkürzel]-[Jahr]-[Monat]-[Tag]", "BEG") }
    assert_equal "BEG-2026-10-08", invoices(:one).reload.invoice_number
    assert_equal "BEG-2026-10-08-02", invoices(:two).reload.invoice_number
    assert_equal "BEG-2026-10-09", InvoiceNumber.new(@workspace.invoices, date: @date + 1, format: "[Kundenkürzel]-[Jahr]-[Monat]-[Tag]", buyer_abbreviation: "BEG").next_number
  end

  test "automatischer Zusatz beachtet die maximale Nummernlaenge" do
    Invoice.where(id: invoices(:one).id).update_all(invoice_number: "A" * 100)
    assert_raises(InvoiceNumber::Invalid) { number("[Kundenkürzel]" * 5, "A" * 20) }
  end

  test "beliebige Zeichen und unbekannte Platzhalter bleiben als Nummerntext erhalten" do
    format = "# / ÄÖ ✓ [Unbekannt]"
    assert_equal format, number(format)
  end

  test "leere und zu lange Formate sowie fehlende Kuerzel werden abgelehnt" do
    [ "", "X" * 81 ].each do |format|
      assert_raises(InvoiceNumber::Invalid) { number(format) }
    end
    error = assert_raises(InvoiceNumber::Invalid) { number("[Kundenkürzel]-[Jahr]") }
    assert_equal :buyer_abbreviation, error.field
    assert_raises(InvoiceNumber::Invalid) { number("[Kundenkürzel]", "A B") }
  end

  test "unbekannte Platzhalter werden als literaltext uebernommen" do
    assert_equal "2026-10-08-[Mehrfachrechnungszähler]", number("[Jahr]-[Monat]-[Tag]-[Mehrfachrechnungszähler]")
  end

  test "alte Platzhalter aus bereits geoeffneten Formularen werden weiterhin verstanden" do
    assert_equal "RE-2026-0001", number("RE-[Jahr]-[Nummer]")
    invoice = Invoice.new(invoice_number_format: "RE-[Jahr]-[Nummer]")
    assert_equal "RE-[Jahr]-[Fortlaufendenummer]", invoice.invoice_number_format
    assert_equal "0001" * 10, number("[Fortlaufendenummer]" * 10)
  end

  test "Migration benennt nur gespeicherte Formate um und erhaelt Rechnungsnummern und Entwurfsinhalt" do
    old_format = "RE-[Jahr]-[Nummer]"
    Invoice.where(id: invoices(:one).id).update_all(invoice_number_format: old_format)
    profile = @workspace.create_business_profile!(invoice_number_format: old_format)
    draft = @workspace.invoice_drafts.create!(data: { "invoice_number_format" => old_format, "buyer_name" => "Text [Nummer]" })
    @workspace.update!(invoice_draft: { "invoice_number_format" => old_format })
    migration = RenameInvoiceSequencePlaceholder.new
    migration.suppress_messages { migration.up }
    new_format = "RE-[Jahr]-[Fortlaufendenummer]"
    assert_equal new_format, invoices(:one).reload.invoice_number_format
    assert_equal "FIXTURE-1", invoices(:one).invoice_number
    assert_equal new_format, profile.reload.invoice_number_format
    assert_equal new_format, draft.reload.data.fetch("invoice_number_format")
    assert_equal "Text [Nummer]", draft.data.fetch("buyer_name")
    assert_equal new_format, @workspace.reload.invoice_draft.fetch("invoice_number_format")
  end

  test "Startwert gilt nur fuer Fortlaufendenummer und ungueltige Werte werden abgelehnt" do
    assert_equal [ "RE-2026-0148", 148, nil ], InvoiceNumber.new(@workspace.invoices, date: @date, format: "RE-[Jahr]-[Fortlaufendenummer]", sequence_start: "148").number_and_sequence
    [ "0", "-1", "1.5", "abc", "1000000000" ].each do |value|
      error = assert_raises(InvoiceNumber::Invalid) { InvoiceNumber.new(@workspace.invoices, date: @date, format: "RE-[Jahr]-[Fortlaufendenummer]", sequence_start: value).next_number }
      assert_equal :invoice_number_start, error.field
    end
    assert_equal "RE-2026", InvoiceNumber.new(@workspace.invoices, date: @date, format: "RE-[Jahr]", sequence_start: "148").next_number
  end

  test "zuletzt verwendete Nummer wird um eins erhoeht und darf nicht zurueckgesetzt werden" do
    service = ->(last) { InvoiceNumber.new(@workspace.invoices, date: @date, last_sequence: last) }
    assert_equal [ "RE-2026-0148", 148, nil ], service.call("147").number_and_sequence
    %w[-1 147.5 abc 999999999].each do |last|
      error = assert_raises(InvoiceNumber::Invalid) { service.call(last).next_number }
      assert_equal :invoice_number_last, error.field
    end
    Invoice.where(id: invoices(:one).id).update_all(issued_on: @date, invoice_number_sequence: 148)
    error = assert_raises(InvoiceNumber::Invalid) { service.call("147").next_number }
    assert_match "2026", error.message
    assert_equal "RE-2026-0149", service.call("148").next_number
    assert_equal "RE-2027-0001", InvoiceNumber.new(@workspace.invoices, date: Date.new(2027, 1, 1), last_sequence: "0").next_number
  end

  test "Tageszaehler beginnt bei 01 und setzt alte Datumsnummern fort" do
    format = "[Kundenkürzel]-[Jahr]-[Monat]-[Tag]-[Tageszähler]"
    assert_equal [ "BEG-2026-10-08-01", nil, 1 ], InvoiceNumber.new(@workspace.invoices, date: @date, format: format, buyer_abbreviation: "BEG").number_and_sequence
    Invoice.where(id: invoices(:one).id).update_all(invoice_number: "BEG-2026-10-08")
    assert_equal "BEG-2026-10-08-02", number(format, "BEG")
    Invoice.where(id: invoices(:two).id).update_all(invoice_number: "BEG-2026-10-08-99")
    2.times { assert_equal "BEG-2026-10-08-100", number(format, "BEG") }
    assert_equal "AND-2026-10-08-01", number(format, "AND")
    assert_equal "BEG-2026-10-09-01", InvoiceNumber.new(@workspace.invoices, date: @date + 1, format: format, buyer_abbreviation: "BEG").next_number
    assert_equal "BEG-2026-10-08-01", InvoiceNumber.new(Workspace.create!.invoices, date: @date, format: format, buyer_abbreviation: "BEG").next_number
    assert_equal "BEG-2026-10-08", invoices(:one).reload.invoice_number
  end

  test "Jahreszaehler wird trotz fehlendem oder ungueltigem Kundenkuerzel ermittelt" do
    format = "RE-[Jahr]-[Fortlaufendenummer]-[Kundenkürzel]"
    [ nil, "A B" ].each do |abbreviation|
      error = assert_raises(InvoiceNumber::Invalid) do
        InvoiceNumber.new(@workspace.invoices, date: @date, format: format, buyer_abbreviation: abbreviation, last_sequence: "1000").next_number
      end
      assert_equal :buyer_abbreviation, error.field
      assert_equal 1001, error.sequence
    end
    Invoice.where(id: invoices(:one).id).update_all(issued_on: @date, invoice_number_sequence: 1005)
    error = assert_raises(InvoiceNumber::Invalid) do
      InvoiceNumber.new(@workspace.invoices, date: @date, format: format, last_sequence: "1000").next_number
    end
    assert_equal :invoice_number_last, error.field
    assert_nil error.sequence
    error = assert_raises(InvoiceNumber::Invalid) do
      InvoiceNumber.new(@workspace.invoices, date: Date.new(2027, 1, 1), format: format).next_number
    end
    assert_equal 1, error.sequence
  end

  test "Kundenkuerzel am Ende verwendet denselben Jahreszaehler" do
    Invoice.where(id: invoices(:one).id).update_all(issued_on: @date, invoice_number_sequence: 41)
    assert_equal "RE-2026-0042-ABE", number("RE-[Jahr]-[Fortlaufendenummer]-[Kundenkürzel]", "abe")
  end

  private

  def number(format, abbreviation = nil)
    InvoiceNumber.new(@workspace.invoices, date: @date, format: format, buyer_abbreviation: abbreviation).next_number
  end
end
