class InvoiceLine < ApplicationRecord
  belongs_to :invoice, inverse_of: :invoice_lines

  UNIT_CODES = {
    "C62" => "Stück",
    "HUR" => "Stunde",
    "DAY" => "Tag",
    "MON" => "Monat"
  }.freeze

  TAX_RATES = [ 19, 7 ].freeze

  def readonly?
    super || !new_record?
  end

  COPIED_ATTRIBUTES = %w[description details quantity unit_price unit_code tax_rate].freeze

  PLURALS = { "HUR" => "Stunden", "DAY" => "Tage", "MON" => "Monate" }.freeze

  validates :description, presence: true
  validates :quantity, numericality: { other_than: 0, greater_than_or_equal_to: -999_999_999.999, less_than_or_equal_to: 999_999_999.999 }
  validate :quantity_sign_matches_invoice_type
  validates :unit_price, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 9_999_999_999.99 }
  validates :unit_code, inclusion: { in: UNIT_CODES.keys }
  validate :tax_rate_allowed
  before_validation :clean_details

  DETAILS_TAGS = %w[p div br strong b em i ul ol li].freeze

  # Beschreibung als HTML für die Rechnung. Ältere Einträge ohne HTML behalten ihre Zeilenumbrüche.
  def details_html
    return "".html_safe if details.blank?

    html = details.match?(/<\w+/) ? details : ActionController::Base.helpers.simple_format(ERB::Util.h(details))
    ActionController::Base.helpers.sanitize(html, tags: DETAILS_TAGS, attributes: [])
  end

  # Reintext für die XRechnung, die kein HTML in der Beschreibung erlaubt.
  def details_text
    return nil if details.blank?

    text = details.gsub(%r{</(p|div|li)>|<br\s*/?>}i, "\n").gsub(/<li>/i, "\n- ")
    text = CGI.unescapeHTML(ActionController::Base.helpers.strip_tags(text)).gsub(/\n{2,}/, "\n").strip
    text.presence
  end

  def tax_rate_percent
    tax_rate.to_d.to_i
  end

  def unit_label
    quantity == 1 ? UNIT_CODES.fetch(unit_code) : PLURALS.fetch(unit_code, UNIT_CODES.fetch(unit_code))
  end

  def line_total
    (quantity.to_d * unit_price.to_d).round(2)
  end

  private

  def quantity_sign_matches_invoice_type
    return unless quantity.present? && invoice

    if invoice.cancellation? && quantity.positive?
      errors.add(:quantity, "muss bei einer Stornorechnung negativ sein")
    elsif !invoice.cancellation? && quantity.negative?
      errors.add(:quantity, "muss größer als 0 sein")
    end
  end

  def clean_details
    return if details.blank?

    cleaned = ActionController::Base.helpers.sanitize(details.gsub(%r{<(script|style)\b.*?</\1>}mi, ""), tags: DETAILS_TAGS, attributes: [])
    self.details = cleaned.gsub(/<[^>]+>/, "").strip.empty? ? nil : cleaned
  end

  def tax_rate_allowed
    return if tax_rate.to_d.zero? || TAX_RATES.include?(tax_rate.to_d.to_i)

    errors.add(:tax_rate, "muss 19 % oder 7 % sein")
  end
end
