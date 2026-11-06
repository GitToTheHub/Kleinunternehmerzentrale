# A quotation and its accepted order retain separate, numbered snapshots.
class SalesDocument < ApplicationRecord
  belongs_to :workspace
  belongs_to :source_offer, class_name: "SalesDocument", optional: true
  has_one :accepted_order, class_name: "SalesDocument", foreign_key: :source_offer_id
  has_many :invoices

  KINDS = { "offer" => "Angebot", "order" => "Auftrag" }.freeze
  INPUT_ATTRIBUTES = (Invoice::COPIED_ATTRIBUTES + %w[issued_on payment_terms iban bic seller_hourly_rate buyer_hourly_rate invoice_lines_attributes]).freeze
  validates :kind, inclusion: { in: KINDS.keys }
  validates :document_date, presence: true
  validates :document_number, uniqueness: { scope: :workspace_id }, allow_blank: true
  validate :content_valid
  validate :source_valid
  validate :editable_record, on: :update
  before_create :remember_customer
  attr_accessor :invoice_number_last
  validate :number_valid
  before_save :assign_number

  def label = KINDS.fetch(kind)
  def offer? = kind == "offer"
  def order? = kind == "order"
  def title = data["title"].presence
  def buyer_name = data["buyer_name"]
  def editable? = !accepted_order && invoices.none?

  def self.input_data(attributes)
    JSON.parse(attributes.to_h.stringify_keys.slice(*INPUT_ATTRIBUTES).to_json)
  end

  def invoice_attributes
    self.class.input_data(data).except("issued_on", "invoice_number_format").merge("currency" => "EUR", "tax_mode" => "small_business")
  end

  def invoice_view
    workspace.invoices.new(self.class.input_data(data).merge("issued_on" => document_date, "billing_kind" => "regular", "customer_update_mode" => "invoice_only",
      "invoice_number_format" => "DOC-[Jahr]-[Fortlaufendenummer]", "currency" => "EUR", "tax_mode" => "small_business"))
  end


  def number_format
    data["invoice_number_format"].presence || (workspace&.business_profile&.invoice_number_format.presence if new_record?) || InvoiceNumber::DEFAULT_FORMAT
  end

  def number_generator(date: document_date, format: number_format, abbreviation: data["buyer_abbreviation"], last: invoice_number_last)
    InvoiceNumber.new(workspace.sales_documents, date: date, format: format, buyer_abbreviation: abbreviation,
      billing_kind: kind, last_sequence: last, number_column: :document_number, date_column: :document_date,
      sequence_column: :number_sequence, sequence_scope: workspace.sales_documents.where(kind: kind))
  end

  def number_unchanged?(format = number_format, last = invoice_number_last)
    persisted? && format == (data_in_database["invoice_number_format"].presence || InvoiceNumber::DEFAULT_FORMAT) && (last.blank? || last.to_s == (number_sequence.to_i - 1).to_s)
  end

  def proposed_number
    return document_number if number_unchanged?
    number_generator.next_number
  rescue InvoiceNumber::Invalid => error
    error.message
  end

  def accept!
    workspace.with_lock do
      reload
      raise ActiveRecord::RecordInvalid, self unless offer?
      workspace.sales_documents.find_by(source_offer_id: id) || workspace.sales_documents.create!(kind: "order", document_date: Date.current, source_offer: self, data: data.deep_dup)
    end
  end

  def active_invoices
    invoices.where(cancelled_invoice_id: nil).includes(:cancellation).reject(&:cancellation)
  end

  def closed? = active_invoices.any? { |invoice| %w[regular final].include?(invoice.billing_kind) }

  private

  def content_valid
    unless data.is_a?(Hash)
      errors.add(:base, "Bitte erfasse die Angaben und Positionen.")
      return
    end
    errors.add(:base, "Angebote und Aufträge werden zunächst nur in Euro ohne Umsatzsteuerausweis unterstützt.") if data["currency"].present? && data["currency"] != "EUR" || data["tax_mode"].present? && data["tax_mode"] != "small_business"
    if data["service_until_on"].present? && data["service_on"].blank?
      errors.add(:base, "Bitte ergänze den Beginn des geplanten Leistungszeitraums.")
    end
    invoice = invoice_view
    if invoice.valid?
      self.total_amount = invoice.total
      cleaned = invoice.attributes.slice(*(INPUT_ATTRIBUTES - %w[invoice_lines_attributes issued_on invoice_number_format]))
      cleaned["invoice_lines_attributes"] = invoice.invoice_lines.each_with_index.to_h { |line, index| [ index.to_s, line.attributes.slice(*InvoiceLine::COPIED_ATTRIBUTES) ] }
      # Missing planned dates stay optional on the offer/order.
      cleaned["service_on"] = data["service_on"].presence
      cleaned["invoice_number_format"] = number_format
      self.data = self.class.input_data(cleaned)
    else
      invoice.errors.full_messages.each { |message| errors.add(:base, message) }
    end
  end

  def source_valid
    return unless source_offer_id
    source = workspace&.sales_documents&.find_by(id: source_offer_id)
    errors.add(:source_offer, "ist kein Angebot aus deinem Bereich") unless order? && source&.offer?
  end

  def editable_record
    errors.add(:base, "Angenommene Angebote und bereits abgerechnete Aufträge bleiben unverändert.") unless editable?
  end

  def remember_customer
    invoice = invoice_view
    invoice.valid?
    customer = Customer.remember(invoice)
    self.data = data.merge("customer_id" => customer.id)
    invoice.invoice_number_format_once = true
    BusinessProfile.remember(invoice)
  end

  def number_valid
    @prepared_number = nil
    return if errors.any? || !workspace || !document_date || number_unchanged?
    @prepared_number = number_generator.number_and_sequence
  rescue InvoiceNumber::Invalid => error
    errors.add(:base, error.message)
  end

  def assign_number
    return unless @prepared_number
    self.document_number, self.number_sequence = @prepared_number.first(2)
    # Date-only formats still need a stable annual sequence for later formats.
    self.number_sequence ||= (workspace.sales_documents.where(kind: kind, document_date: document_date.all_year).maximum(:number_sequence) || 0) + 1
  end
end
