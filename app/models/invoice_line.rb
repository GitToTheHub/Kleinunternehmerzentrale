class InvoiceLine < ApplicationRecord
  include EuroAmounts
  euro_amounts :unit_price
  belongs_to :invoice, inverse_of: :invoice_lines

  UNIT_CODES = {
    "C62" => "Stück",
    "HUR" => "Stunde",
    "DAY" => "Tag",
    "MON" => "Monat",
    "LS" => "Pauschal"
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
  before_validation :normalize_flat_rate_quantity

  DETAILS_TAGS = %w[p div br strong b em i ul ol li a].freeze
  DETAILS_ATTRIBUTES = %w[href].freeze

  # Beschreibung als HTML für die Rechnung. Ältere Einträge ohne HTML behalten ihre Zeilenumbrüche.
  def details_html
    return "".html_safe if details.blank?

    html = details.match?(/<\w+/) ? details : plain_details_html
    sanitized = ActionController::Base.helpers.sanitize(html, tags: DETAILS_TAGS, attributes: DETAILS_ATTRIBUTES)
    fragment = Nokogiri::HTML.fragment(ActionController::Base.helpers.sanitize(format_legacy_list_markers(sanitized), tags: DETAILS_TAGS, attributes: DETAILS_ATTRIBUTES))
    fragment.css("a[href]").each do |link|
      link["target"] = "_blank"
      link["rel"] = "noopener noreferrer"
    end
    fragment.to_html.html_safe
  end

  # Reintext für die XRechnung, die kein HTML in der Beschreibung erlaubt.
  def details_text
    return nil if details.blank?

    fragment = Nokogiri::HTML.fragment(ActionController::Base.helpers.sanitize(details, tags: DETAILS_TAGS, attributes: DETAILS_ATTRIBUTES))
    fragment.css("a").each do |link|
      label = link.text.strip
      address = link["href"]
      text = address.present? && label != address ? (label.present? ? "#{label} (#{address})" : address) : label
      link.replace(Nokogiri::XML::Text.new(text, fragment.document))
    end
    fragment.css("ul, ol").reject { |list| list.ancestors.any? { |parent| %w[ul ol].include?(parent.name) } }.each do |list|
      list.replace(Nokogiri::XML::Text.new("\n#{list_plain_text(list)}\n", fragment.document))
    end
    html_plain_text(fragment.to_html).presence
  end

  def tax_rate_percent
    tax_rate.to_d.to_i
  end

  def unit_label
    quantity == 1 ? UNIT_CODES.fetch(unit_code) : PLURALS.fetch(unit_code, UNIT_CODES.fetch(unit_code))
  end

  def line_total
    billed_quantity = flat_rate? ? (invoice&.cancellation? ? -1 : 1) : quantity.to_d
    (billed_quantity * unit_price.to_d).round(2)
  end

  def flat_rate?
    unit_code == "LS"
  end

  private

  def html_plain_text(html)
    text = html.gsub(%r{</(p|div|li)>|<br\s*/?>}i, "\n")
    CGI.unescapeHTML(ActionController::Base.helpers.strip_tags(text)).gsub(/\n{2,}/, "\n").strip
  end

  def list_plain_text(list, depth = 0)
    list.element_children.select { |child| child.name == "li" }.each_with_index.map do |item, index|
      own_content = item.dup
      own_content.css("ul, ol").remove
      marker = list.name == "ol" ? "#{index + 1}." : "-"
      text = "#{'  ' * depth}#{marker} #{html_plain_text(own_content.to_html)}"
      nested = item.css("ul, ol").reject do |child|
        child.ancestors.take_while { |parent| parent != item }.any? { |parent| %w[ul ol].include?(parent.name) }
      end
      ([ text ] + nested.map { |child| list_plain_text(child, depth + 1) }).join("\n")
    end.join("\n")
  end

  def normalize_flat_rate_quantity
    self.quantity = invoice&.cancellation? ? -1 : 1 if flat_rate?
  end

  def plain_details_html
    lines = details.lines.map(&:chomp)
    blocks = []
    index = 0
    while index < lines.length
      if (match = lines[index].match(/\A\s*[-*•]\s+(.+)\z/))
        items = []
        while match
          items << "<li>#{ERB::Util.h(match[1])}</li>"
          index += 1
          match = lines[index]&.match(/\A\s*[-*•]\s+(.+)\z/)
        end
        blocks << "<ul>#{items.join}</ul>"
      else
        paragraph = []
        while index < lines.length && !lines[index].match?(/\A\s*[-*•]\s+.+\z/)
          paragraph << lines[index]
          index += 1
        end
        blocks << ActionController::Base.helpers.simple_format(ERB::Util.h(paragraph.join("\n"))).to_s
      end
    end
    blocks.join.html_safe
  end

  def format_legacy_list_markers(html)
    fragment = Nokogiri::HTML.fragment(html)
    result = Nokogiri::HTML.fragment("")
    pending_items = []

    flush_list = lambda do
      next if pending_items.empty?

      list = Nokogiri::XML::Node.new("ul", result.document)
      pending_items.each { |item| list.add_child(item) }
      result.add_child(list)
      pending_items.clear
    end

    fragment.children.each do |node|
      first_text = nil
      node.traverse { |child| first_text ||= child if child.text? && !child.text.strip.empty? }
      is_text_list_item = node.element? && %w[p div].include?(node.name) &&
        first_text&.content&.match?(/\A\s*[-–—]\s+/)

      if is_text_list_item
        first_text.content = first_text.content.sub(/\A\s*[-–—]\s+/, "")
        item = Nokogiri::XML::Node.new("li", result.document)
        node.children.each { |child| item.add_child(child.dup) }
        pending_items << item
      else
        flush_list.call
        result.add_child(node.dup)
      end
    end

    flush_list.call
    result.to_html
  end

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

    cleaned = ActionController::Base.helpers.sanitize(details.gsub(%r{<(script|style)\b.*?</\1>}mi, ""), tags: DETAILS_TAGS, attributes: DETAILS_ATTRIBUTES)
    self.details = cleaned.gsub(/<[^>]+>/, "").strip.empty? ? nil : cleaned
  end

  def tax_rate_allowed
    return if tax_rate.to_d.zero? || TAX_RATES.include?(tax_rate.to_d.to_i)

    errors.add(:tax_rate, "muss 19 % oder 7 % sein")
  end
end
