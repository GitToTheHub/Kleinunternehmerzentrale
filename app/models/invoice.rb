class Invoice < ApplicationRecord
  attribute :invoice_number_format, :string, default: -> { InvoiceNumber::DEFAULT_FORMAT }
  include EuroAmounts
  include StagedInvoice
  include OrderBilling
  attribute :received_on, :date
  attribute :received_account, :string, default: "business"
  attribute :received_amount, :decimal
  attribute :buyer_hourly_rate, :decimal
  attr_reader :buyer_hourly_rate_provided
  before_validation { @buyer_hourly_rate_provided = true unless buyer_hourly_rate_before_type_cast.nil? }
  euro_amounts :buyer_hourly_rate
  validates :buyer_hourly_rate, numericality: { greater_than_or_equal_to: 0, less_than: 10_000_000 }, allow_nil: true
  attribute :seller_hourly_rate, :decimal
  attr_reader :seller_hourly_rate_provided
  before_validation { @seller_hourly_rate_provided = true unless seller_hourly_rate_before_type_cast.nil? }
  euro_amounts :seller_hourly_rate
  validates :seller_hourly_rate, numericality: { greater_than_or_equal_to: 0, less_than: 10_000_000 }, allow_nil: true
  euro_amounts :received_amount
  attr_accessor :record_initial_payment
  attr_reader :invoice_number_format_once
  attr_accessor :invoice_number_start, :invoice_number_last
  validate :initial_payment_valid, on: :create
  after_create :record_initial_income

  has_one :payment_entry, class_name: "BookkeepingEntry", inverse_of: :invoice

  belongs_to :workspace
  belongs_to :customer, optional: true
  belongs_to :cancelled_invoice, class_name: "Invoice", optional: true
  belongs_to :corrected_invoice, class_name: "Invoice", optional: true
  validate :correction_reference_valid
  has_one :cancellation, class_name: "Invoice", foreign_key: :cancelled_invoice_id, inverse_of: :cancelled_invoice
  has_many :invoice_lines, inverse_of: :invoice, dependent: :destroy
  accepts_nested_attributes_for :invoice_lines, allow_destroy: true, reject_if: :all_blank

  COPIED_ATTRIBUTES = %w[
    title payment_method
    service_on service_until_on seller_name seller_street seller_postal_code seller_city seller_country seller_email seller_phone
    seller_tax_identifier seller_tax_id_kind seller_vat_id buyer_name buyer_contact_name buyer_street buyer_postal_code buyer_city buyer_country
    currency exchange_rate exchange_rate_on exchange_rate_source
    customer_id buyer_email buyer_leitweg_id buyer_order_number tax_mode buyer_abbreviation invoice_number_format
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

  CURRENCIES = { "EUR" => "Euro (EUR)", "USD" => "US-Dollar (USD)", "GBP" => "Britisches Pfund (GBP)", "CHF" => "Schweizer Franken (CHF)" }.freeze

  TAX_MODES = %w[small_business standard].freeze

  attribute :exchange_rate_quote, :decimal

  attribute :service_period, :boolean
  attribute :customer_update_mode, :string

  before_validation :set_invoice_dates, on: :create
  before_validation :clear_unused_service_end
  before_validation :apply_tax_mode
  before_validation :normalize_country_codes
  before_validation :detect_tax_id_kind
  before_validation :normalize_bank_details
  before_validation :assign_invoice_number, on: :create
  before_create :remember_customer, unless: :cancellation?
  after_create :remember_business_details, unless: :cancellation?

  # Gespeicherte Rechnungen werden nicht mehr geändert. Korrekturen laufen über eine neue Rechnung.
  def readonly?
    super || !new_record?
  end

  validates :issued_on, :service_on, :seller_name, :seller_street, :seller_postal_code,
    :seller_city, :seller_country, :seller_tax_identifier, :seller_tax_id_kind,
    :buyer_name, :buyer_street, :buyer_postal_code, :buyer_city, :buyer_country, presence: true
  validates :currency, inclusion: { in: CURRENCIES.keys }
  validates :exchange_rate, numericality: { greater_than: 0, less_than: 1_000_000_000 }, if: :foreign_currency?
  validates :exchange_rate_on, :exchange_rate_source, presence: true, if: :foreign_currency?
  validates :exchange_rate_source, length: { maximum: 200 }, allow_blank: true
  before_validation :clear_euro_exchange_rate

  validates :seller_phone, length: { maximum: 50 }, allow_blank: true
  validates :seller_country, :buyer_country, inclusion: { in: COUNTRIES.map(&:last), message: "bitte wähle ein Land aus der Liste" }
  validates :seller_tax_id_kind, inclusion: { in: %w[tax_number vat_id] }
  validates :tax_mode, inclusion: { in: TAX_MODES }
  validates :service_until_on, presence: true, if: :service_period?
  validate :standard_lines_have_tax_rate
  validates :payment_method, inclusion: { in: %w[cash transfer other] }, allow_blank: true
  validates :iban, presence: true, if: -> { payment_method == "transfer" }
  validates :title, length: { maximum: 200 }
  validates :invoice_number, uniqueness: { scope: :workspace_id }, allow_blank: true
  validate :customer_selection, on: :create
  validate :has_invoice_line
  validate :cancellable_invoice
  validate :iban_checksum
  validate :payment_due_not_before_issue
  validate :service_period_order

  def self.next_invoice_number(date = Date.current, format: InvoiceNumber::DEFAULT_FORMAT, buyer_abbreviation: nil, sequence_start: nil, last_sequence: nil, billing_kind: "regular", cancellation: false)
    InvoiceNumber.new(all, date: date, format: format, buyer_abbreviation: buyer_abbreviation, sequence_start: sequence_start, last_sequence: last_sequence, billing_kind: billing_kind, cancellation: cancellation).next_number
  end

  def customer_details_changed?
    customer_id.present? && customer && customer.workspace_id == workspace_id && customer.differs_from_invoice?(self)
  end

  def invoice_number_format=(value)
    super(InvoiceNumber.normalize_format(value))
  end

  def invoice_number_format_once=(value)
    @invoice_number_format_once = ActiveModel::Type::Boolean.new.cast(value)
  end

  def proposed_invoice_number
    workspace.invoices.next_invoice_number(issued_on || Date.current, format: invoice_number_format, buyer_abbreviation: buyer_abbreviation, sequence_start: invoice_number_start, last_sequence: invoice_number_last, billing_kind: billing_kind, cancellation: cancellation?)
  rescue InvoiceNumber::Invalid => error
    error.field == :buyer_abbreviation ? "Kundenkürzel ergänzen" : "Rechnungsnummernformat prüfen"
  end

  def cancellation?
    cancelled_invoice_id.present? || cancelled_invoice.present?
  end

  # Eine Stornorechnung hebt die Rechnung auf: gleiche Angaben, aber die Mengen sind negativ.
  def build_cancellation
    cancellation_format = invoice_number_format.match?(/\[(Rechnungsart|Rechnungstyp)\]/) ? invoice_number_format : "ST-[Jahr]-[Fortlaufendenummer]"
    cancellation = workspace.invoices.new(
      attributes.slice(*COPIED_ATTRIBUTES).merge(cancelled_invoice: self, issued_on: Date.current, invoice_number_format: cancellation_format)
    )
    cancellation.sales_document = sales_document
    cancellation.order_snapshot = order_snapshot.deep_dup
    cancellation.allocation_mode = allocation_mode
    cancellation.allocation_percent = allocation_percent
    cancellation.allocation_amount = allocation_amount
    cancellation.billing_kind = billing_kind
    cancellation.billing_root_id = billing_root_id
    cancellation.deducted_payments = deducted_payments.map { |payment| payment.merge("amount" => (-payment.fetch("amount").to_d).to_s("F")) }
    invoice_lines.each do |line|
      cancellation.invoice_lines.build(line.attributes.slice(*InvoiceLine::COPIED_ATTRIBUTES).merge("quantity" => -line.quantity))
    end
    cancellation
  end

  def correction_notice
    return unless corrected_invoice

    "Diese Rechnung korrigiert Rechnung #{corrected_invoice.invoice_number} vom #{corrected_invoice.issued_on.strftime('%d.%m.%Y')}."
  end

  def effective_payment_method
    payment_method.presence || (iban.present? ? "transfer" : "other")
  end

  def correction_reference_valid
    return if corrected_invoice_id.blank?

    if corrected_invoice.nil? || corrected_invoice.workspace_id != workspace_id || corrected_invoice.cancellation? || !corrected_invoice.cancellation
      errors.add(:corrected_invoice, "muss eine stornierte Rechnung aus deinem Bereich sein")
    end
  end

  def payment_received? = paid? || payment_entry.present?

  def initial_payment_valid
    return unless record_initial_payment && paid? && !cancellation? && payment_total.positive?

    payment = initial_income
    payment.valid?
    payment.errors.each { |error| errors.add(:base, "Zahlung: #{error.full_message}") }
    errors.add(:received_on, "darf nicht in der Zukunft liegen") if received_on && received_on > Date.current
  end

  def initial_income
    BookkeepingEntry.new(workspace: workspace, kind: "income", category: "income_small", paid_on: received_on,
      payment_account: received_account, amount: foreign_currency? ? received_amount : payment_total_in_euros,
      reference: invoice_number, description: payment_description)
  end

  def record_initial_income
    return unless record_initial_payment && paid? && !cancellation? && payment_total.positive?

    payment = initial_income
    payment.invoice = self
    payment.save!
  end

  def payment_description
    [ "Zahlung zu #{billing_label} #{invoice_number}", title.presence, buyer_name ].compact.join(" · ")
  end

  def payment_recordable? = !cancellation? && !cancellation && !standard_taxed? && payment_total.positive?

  def payment_status
    return "Stornorechnung" if cancellation?
    return "Storniert" if cancellation
    return "Kein Zahlbetrag" if payment_total.zero?
    if payment_entry && payment_entry.refunds.exists?
      return payment_entry.refundable_amount.zero? ? "Vollständig zurückgezahlt" : "Teilweise zurückgezahlt"
    end
    return "Bezahlt" if payment_received?

    payment_due_on && payment_due_on < Date.current ? "Zahlung überfällig" : "Zahlung ausstehend"
  end

  def amount_due
    paid? && !cancellation? ? 0.to_d : payment_total
  end

  # Nur ein einheitlicher Stundensatz darf als neue Vorgabe vorgeschlagen werden.
  def uniform_hourly_rate
    return if foreign_currency?

    rates = active_lines.select { |line| line.unit_code == "HUR" && line.unit_price.to_d.positive? }.map(&:unit_price).uniq
    rates.first if rates.one?
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

  def exchange_rate_quote
    self[:exchange_rate_quote] || (BigDecimal("1") / exchange_rate).round(8) if exchange_rate&.positive? || self[:exchange_rate_quote]
  end

  def exchange_rate_quote=(value)
    super
    quote = self[:exchange_rate_quote]
    self.exchange_rate = quote&.positive? ? (BigDecimal("1") / quote).round(8) : quote
  end

  def foreign_currency?
    currency != "EUR"
  end

  def total_in_euros
    foreign_currency? ? (total * exchange_rate).round(2) : total
  end

  def sepa_buyer?
    SEPA_COUNTRIES.include?(buyer_country.to_s.upcase)
  end

  private

  def clear_euro_exchange_rate
    return if foreign_currency?

    self.exchange_rate = nil
    self.exchange_rate_on = nil
    self.exchange_rate_source = nil
  end

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
    return unless service_period? && service_on && service_until_on && service_until_on <= service_on
    # Historische Rechnungen mit gleichem Von-/Bis-Datum bleiben unverändert stornierbar.
    return if cancellation? && service_until_on == service_on

    errors.add(:service_until_on, "muss nach dem Von-Datum liegen. Für einen einzelnen Tag lass das Bis-Feld leer.")
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
    return unless workspace && issued_on

    self.buyer_abbreviation = buyer_abbreviation.to_s.strip.upcase.presence
    self.invoice_number, self.invoice_number_sequence, self.invoice_number_daily_sequence = InvoiceNumber.new(workspace.invoices,
      date: issued_on, format: invoice_number_format, buyer_abbreviation: buyer_abbreviation, sequence_start: invoice_number_start, last_sequence: invoice_number_last, billing_kind: billing_kind, cancellation: cancellation?).number_and_sequence
  rescue InvoiceNumber::Invalid => error
    self.invoice_number = nil
    self.invoice_number_sequence = nil
    self.invoice_number_daily_sequence = nil
    errors.add(error.field, error.message)
  end

  def customer_selection
    if customer_id.present? && (!customer || customer.workspace_id != workspace_id)
      errors.add(:customer_id, "ist nicht verfügbar. Bitte wähle einen Kunden aus deinem Bereich.")
    elsif !cancellation? && customer_details_changed? && !%w[update invoice_only].include?(customer_update_mode)
      errors.add(:customer_update_mode, "bitte wähle, ob die Änderungen gespeichert werden oder nur für diese Rechnung gelten sollen.")
    end
  end

  def remember_customer
    self.customer = Customer.remember(self)
  end

  def remember_business_details
    BusinessProfile.remember(self)
  end

  def cancellable_invoice
    return unless cancelled_invoice

    if cancelled_invoice.settled_in_final?
      errors.add(:base, "Storniere zuerst die Schlussrechnung dieses Auftrags.")
    elsif cancelled_invoice.workspace_id != workspace_id
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
