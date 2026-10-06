require "csv"
require "zip"

# Packt alle Daten eines Bereichs in eine ZIP-Datei: Rechnungen und Positionen als CSV
# (öffnet sich in Excel), dazu Kundinnen/Kunden, Absenderangaben und je Rechnung die XRechnung-XML.
class DataExport
  def initialize(workspace)
    @workspace = workspace
  end

  def call
    invoices = @workspace.invoices.includes(:invoice_lines, :cancelled_invoice).order(:issued_on, :id).to_a
    Zip::OutputStream.write_buffer do |zip|
      add(zip, "rechnungen.csv", invoices_csv(invoices))
      add(zip, "positionen.csv", lines_csv(invoices))
      add(zip, "kunden.csv", customers_csv)
      add(zip, "absender.csv", profile_csv)
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
    value.match?(/\A[=+\-@\t\r]/) && !value.match?(/\A-?\d+([.,]\d+)?\z/) ? "'#{value}" : value
  end

  def invoices_csv(invoices)
    csv(%w[Rechnungsnummer Rechnungsdatum Leistungsdatum Leistungsende Storno_zu Absender Kunde Kunde_Strasse Kunde_PLZ Kunde_Ort Kunde_Land
           Netto Steuer Brutto Zahlungsziel IBAN Zahlungshinweis],
      invoices.map do |i|
        [ i.invoice_number, i.issued_on, i.service_on, i.service_until_on, i.cancelled_invoice&.invoice_number, i.seller_name,
          i.buyer_name, i.buyer_street, i.buyer_postal_code, i.buyer_city, i.buyer_country,
          i.net_total, i.tax_total, i.total, i.payment_due_on, i.iban, i.payment_terms ]
      end)
  end

  def lines_csv(invoices)
    csv(%w[Rechnungsnummer Beschreibung Menge Einheit Einzelpreis Steuersatz],
      invoices.flat_map do |i|
        i.invoice_lines.map { |l| [ i.invoice_number, l.details_text.presence || l.description, l.quantity, l.unit_code, l.unit_price, l.tax_rate ] }
      end)
  end

  def customers_csv
    csv(%w[Name Strasse PLZ Ort Land E-Mail Leitweg-ID],
      @workspace.customers.order(:name).map { |c| [ c.name, c.street, c.postal_code, c.city, c.country, c.email, c.leitweg_id ] })
  end

  def profile_csv
    csv(%w[Name Strasse PLZ Ort Land E-Mail Steuernummer IBAN BIC],
      [ @workspace.business_profile ].compact.map { |p| [ p.name, p.street, p.postal_code, p.city, p.country, p.email, p.tax_identifier, p.iban, p.bic ] })
  end

  def xrechnung(invoice)
    return if invoice.seller_email.blank? || invoice.buyer_email.blank?

    XrechnungGenerator.new(invoice).call
  end
end
