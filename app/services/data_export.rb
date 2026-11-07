require "csv"
require "zip"

# Packt alle Daten eines Bereichs in eine ZIP-Datei: Rechnungen und Positionen als CSV
# (öffnet sich in Excel), dazu Kundinnen/Kunden, Absenderangaben und je Rechnung die XRechnung-XML.
class DataExport
  def initialize(workspace)
    @workspace = workspace
  end

  def call
    invoices = @workspace.invoices.includes(:invoice_lines, :cancelled_invoice, :cancellation, :payment_entry).order(:issued_on, :id).to_a
    Zip::OutputStream.write_buffer do |zip|
      add(zip, "angebote-und-auftraege.json", JSON.pretty_generate(@workspace.sales_documents.order(:id).map(&:attributes)))
      add(zip, "rechnungs-auftragsbezug.json", JSON.pretty_generate(invoices.select { |invoice| invoice.sales_document_id || invoice.staged_invoice? || invoice.order_snapshot.present? }.map { |invoice| { invoice_id: invoice.id, sales_document_id: invoice.sales_document_id, order_snapshot: invoice.order_snapshot, allocation_mode: invoice.allocation_mode, allocation_percent: invoice.allocation_percent, allocation_amount: invoice.allocation_amount } }))
      add(zip, "einstellungen.json", JSON.pretty_generate(@workspace.workflow))
      add(zip, "rechnungen.csv", invoices_csv(invoices))
      add(zip, "positionen.csv", lines_csv(invoices))
      add(zip, "kunden.csv", customers_csv)
      add(zip, "absender.csv", profile_csv)
      if @workspace.bookkeeping_entries.exists?
        add(zip, "buchhaltung.csv", csv(%w[Zahlungsdatum Steuerjahr Art Kategorie Beschreibung Belegnummer Betrag_EUR Steueranteil_EUR Abziehbar_Prozent Konto Rueckzahlung Rechnung_ID Urspruenglicher_Vorgang_ID Betrieblich_Prozent Nutzungsbegruendung Bargeldverwendung Bargeld_privat_EUR],
          @workspace.bookkeeping_entries.order(:paid_on, :id).map { |e| [ e.paid_on, e.effective_year, BookkeepingEntry::KINDS.fetch(e.kind), e.effective_category, e.description, e.reference, e.amount, e.vat_amount, e.deductible_percent, e.payment_account, e.reversal, e.invoice_id, e.original_entry_id, e.business_percent, e.usage_notes, e.cash_usage, e.cash_private_amount ] }))
      end
      if @workspace.business_assets.exists?
        assets = @workspace.business_assets.includes(:asset_depreciations, :asset_private_uses).order(:acquired_on, :id)
        add(zip, "anlagegueter.csv", csv(%w[ID Bezeichnung Beleg Zugang Herkunft Gruppe Kosten_EUR Methode Nutzungsdauer GWG_Nettowert_EUR Zahlungsdatum Konto Vorsteuer_EUR Abgangsdatum Abgangsart Entnahmewert_EUR Entnahme_USt_EUR Steuerlicher_Abgang Hinweise Betriebliche_Nutzung_Prozent Nutzungsgrundlage],
          assets.map { |a| [ a.id, a.name, a.reference, a.acquired_on, a.origin, a.category, a.cost, a.depreciation_method, a.useful_life, a.gwg_net_value, a.paid_on, a.payment_account, a.input_vat, a.disposed_on, a.disposal_kind, a.withdrawal_value, a.withdrawal_vat, a.disposal_recognized_on, a.notes, a.business_use_percent, a.usage_basis ] }))
        add(zip, "anlagegueter-private-nutzung.csv", csv(%w[Anlagegut_ID Jahr Betrieblich_Prozent Berechnung Manueller_Wert_EUR Beruecksichtigter_Wert_EUR Grundlage],
          assets.flat_map { |asset| asset.asset_private_uses.map { |usage| [ asset.id, usage.year, usage.business_percent, usage.calculation_mode, usage.manual_amount, usage.amount, usage.basis ] } }))
        add(zip, "abschreibungen.csv", csv(%w[Anlagegut_ID Jahr AfA_EUR Sonder_AfA_EUR Begruendung],
          assets.flat_map { |a| a.asset_depreciations.map { |d| [ a.id, d.year, d.amount, d.special_amount, d.reason ] } }))
      end
      if @workspace.euer_adjustments.exists?
        add(zip, "euer-ergaenzungen.csv", csv(%w[Jahr Position Betrag_EUR Begruendung],
          @workspace.euer_adjustments.order(:year, :id).map { |a| [ a.year, a.field_key, a.amount, a.description ] }))
      end
      if @workspace.euer_statements.exists?
        add(zip, "euer-betriebsangaben.json", JSON.pretty_generate(@workspace.euer_statements.order(:year).map { |item| { year: item.year, details: item.details } }))
      end
      if @workspace.euer_expense_policies.exists?
        add(zip, "euer-ausgabenmethoden.json", JSON.pretty_generate(@workspace.euer_expense_policies.order(:year).map do |item|
          { year: item.year, deduction_method: item.deduction_method, eligibility_confirmed: item.eligibility_confirmed,
            home_office_method: item.home_office_method, home_days: item.home_days, home_months: item.home_months,
            home_basis: item.home_basis, home_eligibility_confirmed: item.home_eligibility_confirmed,
            daycare_rows: item.daycare_rows, daycare_eligibility_confirmed: item.daycare_eligibility_confirmed,
            updated_at: item.updated_at }
        end))
      end
      if @workspace.bookkeeping_imports.exists?
        add(zip, "euer-uebernahmen-betriebsangaben.json", JSON.pretty_generate(@workspace.bookkeeping_imports.order(:year).map { |item| { year: item.year, details: item.details, notes: item.notes } }))
        add(zip, "euer-uebernahmen.csv", csv(%w[Jahr Zeitraum_bis Quelle Position Betrag_EUR Anlagegueter_separat],
          @workspace.bookkeeping_imports.order(:year).flat_map { |import| import.field_amounts.map { |key, amount| [ import.year, import.covered_through, import.source, key, amount, import.assets_managed_separately ] } }))
      end
      @workspace.invoice_drafts.active.order(:created_at, :id).each do |draft|
        add(zip, "entwuerfe/#{draft.id}.json", JSON.pretty_generate(draft.data))
      end
      add(zip, "entwuerfe/bearbeitungsbereiche.json", JSON.pretty_generate(@workspace.invoice_drafts.active.order(:id).pluck(:id, :resume_section).to_h))
      invoices.each do |invoice|
        xml = xrechnung(invoice)
        add(zip, "xrechnung/#{invoice.invoice_number}.xml", xml) if xml
      end
    end.string
  end

  private

  def add(zip, name, content)
    zip.put_next_entry(name)
    zip.write(content)
  end

  # Excel erkennt UTF-8 nur mit Byte-Order-Mark und Semikolon als Trennzeichen (deutsche Einstellung).
  def csv(headers, rows)
    "\uFEFF" + CSV.generate(col_sep: ";") do |out|
      out << headers
      rows.each { |row| out << row.map { |value| safe(value) } }
    end
  end

  # Verhindert, dass Tabellenprogramme Zellen als Formel ausführen.
  def safe(value)
    value = value.to_s
    value.match?(/\A[=+\-@\t\r\n]/) && !value.match?(/\A-?\d+([.,]\d+)?\z/) ? "'#{value}" : value
  end

  def invoices_csv(invoices)
    csv(%w[Rechnungsnummer Rechnungsdatum Leistungsdatum Leistungsende Storno_zu Absender Kunde Kundenkontakt Kunde_Strasse Kunde_PLZ Kunde_Ort Kunde_Land
           Netto Steuer Brutto Zahlungsziel IBAN Zahlungshinweis Nummernformat Kundenkuerzel Nummernzaehler Tageszaehler Kunden_ID Absender_E-Mail Absender_Telefon Waehrung Euro_Umrechnungskurs Kursdatum Kursquelle Gesamtbetrag_EUR Rechnungstitel Zahlungsart Bereits_bezahlt Offener_Betrag Korrigiert_Rechnung Zahlungsstatus Zahlungseingang Zahlung_EUR Buchung_ID Rechnung_ID Rechnungsart Auftrag_Erstrechnung_ID Angerechnete_Zahlungen_JSON Zahlbetrag],
      invoices.map do |i|
        [ i.invoice_number, i.issued_on, i.service_on, i.service_until_on, i.cancelled_invoice&.invoice_number, i.seller_name,
          i.buyer_name, i.buyer_contact_name, i.buyer_street, i.buyer_postal_code, i.buyer_city, i.buyer_country,
          i.net_total, i.tax_total, i.total, i.payment_due_on, i.iban, i.payment_terms, i.invoice_number_format, i.buyer_abbreviation, i.invoice_number_sequence, i.invoice_number_daily_sequence, i.customer_id, i.seller_email, i.seller_phone, i.currency, i.exchange_rate, i.exchange_rate_on, i.exchange_rate_source, i.total_in_euros, i.title, i.effective_payment_method, i.paid?, i.amount_due, i.corrected_invoice&.invoice_number, i.payment_status, i.payment_entry&.paid_on, i.payment_entry&.amount, i.payment_entry&.id, i.id, i.billing_kind, i.billing_root_id_for_order, i.deducted_payments.to_json, i.payment_total ]
      end)
  end

  def lines_csv(invoices)
    csv(%w[Rechnungsnummer Beschreibung Menge Einheit Einzelpreis Steuersatz Waehrung],
      invoices.flat_map do |i|
        i.invoice_lines.map { |l| [ i.invoice_number, l.details_text.presence || l.description, l.quantity, l.unit_code, l.unit_price, l.tax_rate, i.currency ] }
      end)
  end

  def customers_csv
    csv(%w[Name Ansprechpartner Strasse PLZ Ort Land E-Mail Leitweg-ID Kundenkuerzel Kunden_ID],
      @workspace.customers.order(:name).map { |c| [ c.name, c.contact_name, c.street, c.postal_code, c.city, c.country, c.email, c.leitweg_id, c.invoice_abbreviation, c.id ] })
  end

  def profile_csv
    csv(%w[Name Strasse PLZ Ort Land E-Mail Steuernummer IBAN BIC Nummernformat Telefon],
      [ @workspace.business_profile ].compact.map { |p| [ p.name, p.street, p.postal_code, p.city, p.country, p.email, p.tax_identifier, p.iban, p.bic, p.invoice_number_format, p.phone ] })
  end

  def xrechnung(invoice)
    return if invoice.seller_email.blank? || invoice.buyer_email.blank?

    XrechnungGenerator.new(invoice).call
  end
end
