class Invoice < ApplicationRecord
  belongs_to :workspace
  belongs_to :cancelled_invoice, class_name: "Invoice", optional: true
  has_one :cancellation, class_name: "Invoice", foreign_key: :cancelled_invoice_id, inverse_of: :cancelled_invoice
  has_many :invoice_lines, inverse_of: :invoice, dependent: :destroy
  accepts_nested_attributes_for :invoice_lines, allow_destroy: true, reject_if: :all_blank

  COPIED_ATTRIBUTES = %w[
    service_on service_until_on seller_name seller_street seller_postal_code seller_city seller_country seller_email
    seller_tax_identifier seller_tax_id_kind seller_vat_id buyer_name buyer_street buyer_postal_code buyer_city buyer_country
    buyer_email buyer_leitweg_id buyer_order_number tax_mode
  ].freeze

  # IBAN-Längen je Land (SWIFT-IBAN-Register).
  IBAN_LENGTHS = {
    "AD" => 24, "AE" => 23, "AL" => 28, "AT" => 20, "BA" => 20, "BE" => 16, "BG" => 22, "CH" => 21,
    "CY" => 28, "CZ" => 24, "DE" => 22, "DK" => 18, "EE" => 20, "ES" => 24, "FI" => 18, "FR" => 27,
    "GB" => 22, "GI" => 23, "GR" => 27, "HR" => 21, "HU" => 28, "IE" => 22, "IS" => 26, "IT" => 27,
    "LI" => 21, "LT" => 20, "LU" => 20, "LV" => 21, "MC" => 27, "MD" => 24, "ME" => 22, "MK" => 19,
    "MT" => 31, "NL" => 18, "NO" => 15, "PL" => 28, "PT" => 25, "RO" => 24, "RS" => 22, "SA" => 24,
    "SE" => 24, "SI" => 19, "SK" => 24, "SM" => 27, "TR" => 26, "VA" => 22, "XK" => 20
  }.freeze

  # Länder im SEPA-Raum: Dort genügt die IBAN, die BIC ist nicht nötig.
  SEPA_COUNTRIES = %w[
    DE AD AL BE BG CH CY CZ DK EE ES FI FR GB GR HR HU IE IS IT LI LT LU LV MC MD ME MK MT NL NO AT PL PT RO RS SE SI SK SM
  ].freeze

  COUNTRIES = [
    [ "Deutschland", "DE" ],
    [ "Albanien", "AL" ],
    [ "Andorra", "AD" ],
    [ "Australien", "AU" ],
    [ "Belgien", "BE" ],
    [ "Bosnien und Herzegowina", "BA" ],
    [ "Brasilien", "BR" ],
    [ "Bulgarien", "BG" ],
    [ "China", "CN" ],
    [ "Dänemark", "DK" ],
    [ "Estland", "EE" ],
    [ "Finnland", "FI" ],
    [ "Frankreich", "FR" ],
    [ "Griechenland", "GR" ],
    [ "Indien", "IN" ],
    [ "Irland", "IE" ],
    [ "Island", "IS" ],
    [ "Israel", "IL" ],
    [ "Italien", "IT" ],
    [ "Japan", "JP" ],
    [ "Kanada", "CA" ],
    [ "Kosovo", "XK" ],
    [ "Kroatien", "HR" ],
    [ "Lettland", "LV" ],
    [ "Liechtenstein", "LI" ],
    [ "Litauen", "LT" ],
    [ "Luxemburg", "LU" ],
    [ "Malta", "MT" ],
    [ "Mexiko", "MX" ],
    [ "Moldau", "MD" ],
    [ "Monaco", "MC" ],
    [ "Montenegro", "ME" ],
    [ "Neuseeland", "NZ" ],
    [ "Niederlande", "NL" ],
    [ "Nordmazedonien", "MK" ],
    [ "Norwegen", "NO" ],
    [ "Österreich", "AT" ],
    [ "Polen", "PL" ],
    [ "Portugal", "PT" ],
    [ "Rumänien", "RO" ],
    [ "San Marino", "SM" ],
    [ "Schweden", "SE" ],
    [ "Schweiz", "CH" ],
    [ "Serbien", "RS" ],
    [ "Singapur", "SG" ],
    [ "Slowakei", "SK" ],
    [ "Slowenien", "SI" ],
    [ "Spanien", "ES" ],
    [ "Südafrika", "ZA" ],
    [ "Südkorea", "KR" ],
    [ "Tschechien", "CZ" ],
    [ "Türkei", "TR" ],
    [ "Ukraine", "UA" ],
    [ "Ungarn", "HU" ],
    [ "Vereinigte Arabische Emirate", "AE" ],
    [ "Vereinigte Staaten", "US" ],
    [ "Vereinigtes Königreich", "GB" ],
    [ "Zypern", "CY" ]
  ].freeze

  TAX_MODES = %w[small_business standard].freeze

  attribute :service_period, :boolean

  before_validation :set_invoice_dates, on: :create
  before_validation :clear_unused_service_end
  before_validation :apply_tax_mode
  before_validation :normalize_country_codes
  before_validation :detect_tax_id_kind
  before_validation :normalize_bank_details
  before_create :assign_invoice_number
  after_create :remember_business_details, unless: :cancellation?

  # Gespeicherte Rechnungen werden nicht mehr geändert. Korrekturen laufen über eine neue Rechnung.
  def readonly?
    super || !new_record?
  end

  validates :issued_on, :service_on, :seller_name, :seller_street, :seller_postal_code,
    :seller_city, :seller_country, :seller_tax_identifier, :seller_tax_id_kind,
    :buyer_name, :buyer_street, :buyer_postal_code, :buyer_city, :buyer_country, presence: true
  validates :seller_country, :buyer_country, inclusion: { in: COUNTRIES.map(&:last), message: "bitte wähle ein Land aus der Liste" }
  validates :seller_tax_id_kind, inclusion: { in: %w[tax_number vat_id] }
  validates :tax_mode, inclusion: { in: TAX_MODES }
  validate :standard_lines_have_tax_rate
  validates :invoice_number, uniqueness: { scope: :workspace_id }, allow_blank: true
  validate :has_invoice_line
  validate :cancellable_invoice
  validate :iban_checksum
  validate :payment_due_not_before_issue
  validate :service_period_order

  # Fortlaufende Nummer je Kalenderjahr, zum Beispiel RE-2026-0001.
  def self.next_invoice_number(date = Date.current)
    prefix = "RE-#{date.year}-"
    last = where("invoice_number LIKE ?", "#{prefix}%").pluck(:invoice_number).map { |n| n.delete_prefix(prefix).to_i }.max || 0
    "#{prefix}#{(last + 1).to_s.rjust(4, "0")}"
  end

  def cancellation?
    cancelled_invoice_id.present? || cancelled_invoice.present?
  end

  # Eine Stornorechnung hebt die Rechnung auf: gleiche Angaben, aber die Mengen sind negativ.
  def build_cancellation
    cancellation = workspace.invoices.new(
      attributes.slice(*COPIED_ATTRIBUTES).merge(cancelled_invoice: self, issued_on: Date.current)
    )
    invoice_lines.each do |line|
      cancellation.invoice_lines.build(line.attributes.slice(*InvoiceLine::COPIED_ATTRIBUTES).merge("quantity" => -line.quantity))
    end
    cancellation
  end

  # Preis der letzten Stunden-Position, die später als Stundensatz vorgeschlagen wird.
  def latest_hourly_rate
    invoice_lines.reverse.find { |line| line.unit_code == "HUR" && line.unit_price.to_d.positive? }&.unit_price
  end

  def service_period?
    service_period.nil? ? service_until_on.present? : service_period
  end

  def standard_taxed?
    tax_mode == "standard"
  end

  # Nettosumme aller Positionen. Beim Kleinunternehmer ist das zugleich der Gesamtbetrag.
  def net_total
    active_lines.sum(&:line_total)
  end

  # Steuerbeträge je Steuersatz, jeweils aus der Summe aller Positionen mit diesem Satz berechnet.
  def tax_groups
    return [] unless standard_taxed?

    active_lines.group_by(&:tax_rate_percent).sort.reverse.map do |rate, lines|
      net = lines.sum(&:line_total)
      { rate: rate, net: net, tax: (net * rate / 100).round(2) }
    end
  end

  def tax_total
    tax_groups.sum { |group| group[:tax] }
  end

  def total
    net_total + tax_total
  end

  def sepa_buyer?
    SEPA_COUNTRIES.include?(buyer_country.to_s.upcase)
  end

  private

  def set_invoice_dates
    self.issued_on ||= Date.current
    self.service_on ||= issued_on
  end

  def active_lines
    invoice_lines.reject(&:marked_for_destruction?)
  end

  # Der Kleinunternehmer weist keine Umsatzsteuer aus, daher gilt für alle Positionen 0 %.
  def apply_tax_mode
    active_lines.each { |line| line.tax_rate = 0 } unless standard_taxed?
  end

  def standard_lines_have_tax_rate
    return unless standard_taxed?

    errors.add(:base, "Bitte wähle für jede Position einen Umsatzsteuersatz") if active_lines.any? { |line| line.tax_rate.to_d.zero? }
  end

  def clear_unused_service_end
    self.service_until_on = nil unless service_period?
  end

  def service_period_order
    return unless service_period? && service_on && service_until_on && service_until_on < service_on

    errors.add(:service_until_on, "darf nicht vor dem Beginn der Leistung liegen")
  end

  def normalize_country_codes
    self.seller_country = seller_country&.upcase
    self.buyer_country = buyer_country&.upcase
  end

  # Eine Umsatzsteuer-ID beginnt mit einem Ländercode (z. B. DE123456789), eine Steuernummer besteht aus Ziffern.
  def detect_tax_id_kind
    self.seller_tax_identifier = seller_tax_identifier&.strip
    return if seller_tax_identifier.blank?

    self.seller_tax_id_kind = seller_tax_identifier.match?(/\A[A-Za-z]{2}/) ? "vat_id" : "tax_number"
  end

  def normalize_bank_details
    self.iban = iban&.gsub(/\s+/, "")&.upcase.presence
    self.bic = (bic&.gsub(/\s+/, "")&.upcase.presence unless sepa_buyer?)
  end

  # Prüft Aufbau und Prüfziffer (Modulo 97) der IBAN.
  def iban_checksum
    return if iban.blank?

    expected = IBAN_LENGTHS[iban[0, 2]]
    if expected && iban.length != expected
      errors.add(:iban, "hat die falsche Länge: #{iban[0, 2]}-IBANs haben #{expected} Zeichen")
      return
    end

    valid = iban.match?(/\A[A-Z]{2}\d{2}[A-Z0-9]{11,30}\z/) &&
      (iban[4..] + iban[0, 4]).chars.map { |c| c.to_i(36) }.join.to_i % 97 == 1
    errors.add(:iban, "ist ungültig, bitte prüfe die Eingabe") unless valid
  end

  def payment_due_not_before_issue
    return unless payment_due_on && issued_on && payment_due_on < issued_on

    errors.add(:payment_due_on, "darf nicht vor dem Rechnungsdatum liegen")
  end

  def assign_invoice_number
    self.invoice_number = workspace.invoices.next_invoice_number(issued_on)
  end

  def remember_business_details
    BusinessProfile.remember(self)
    Customer.remember(self)
  end

  def cancellable_invoice
    return unless cancelled_invoice

    if cancelled_invoice.workspace_id != workspace_id
      errors.add(:cancelled_invoice, "gehört nicht zu deinem Bereich")
    elsif cancelled_invoice.cancellation? || Invoice.where(cancelled_invoice_id: cancelled_invoice.id).where.not(id: id).exists?
      errors.add(:base, "Diese Rechnung wurde schon storniert oder ist selbst eine Stornorechnung.")
    end
  end

  def has_invoice_line
    return if invoice_lines.reject(&:marked_for_destruction?).any?

    errors.add(:invoice_lines, "mindestens eine Rechnungsposition ist erforderlich")
  end
end
