# Formats and proposes numbers without reserving them. Final assignment happens under the workspace lock.
class InvoiceNumber
  DEFAULT_FORMAT = "[Rechnungsart]-[Jahr]-[Fortlaufendenummer]".freeze

  TYPE_CODES = { "regular" => "RE", "advance" => "ANZ", "progress" => "ABS", "final" => "SR", "offer" => "AN", "order" => "AU" }.freeze

  class Invalid < StandardError
    attr_reader :field, :sequence

    def initialize(message, field: :invoice_number_format, sequence: nil)
      @field = field
      @sequence = sequence
      super(message)
    end
  end

  def self.normalize_format(format)
    format.to_s.gsub("[Nummer]", "[Fortlaufendenummer]")
  end

  def initialize(invoices, date:, format: DEFAULT_FORMAT, buyer_abbreviation: nil, sequence_start: nil, last_sequence: nil, billing_kind: "regular", cancellation: false, number_column: :invoice_number, date_column: :issued_on, sequence_column: :invoice_number_sequence, sequence_scope: nil)
    @type_code = cancellation ? "ST" : TYPE_CODES.fetch(billing_kind) { raise Invalid.new("Bitte wähle eine gültige Rechnungsart.", field: :billing_kind) }
    @sequence_start = sequence_start.to_s.strip.presence
    @last_sequence = last_sequence.to_s.strip.presence
    @invoices = invoices
    @number_column, @date_column, @sequence_column = number_column, date_column, sequence_column
    @sequence_scope = sequence_scope || invoices
    @date = date
    @format = self.class.normalize_format(format)
    @abbreviation = buyer_abbreviation.to_s.strip.upcase
  end

  def next_number
    number_and_sequence.first
  end

  def number_and_sequence
    validate_format!
    values = { "[Rechnungsart]" => @type_code, "[Rechnungstyp]" => @type_code, "[Kundenkürzel]" => @abbreviation, "[Jahr]" => @date.strftime("%Y"), "[Monat]" => @date.strftime("%m"), "[Tag]" => @date.strftime("%d") }
    numbers = @invoices.pluck(@number_column).to_set
    sequence = @format.include?("[Fortlaufendenummer]") ? next_sequence(numbers) : nil
    if @last_sequence && sequence
      unless @last_sequence.match?(/\A[0-9]{1,9}\z/) && @last_sequence.to_i.between?(0, 999999998)
        raise Invalid.new("Bitte gib die zuletzt verwendete Nummer als ganze Zahl zwischen 0 und 999999998 ein.", field: :invoice_number_last)
      end
      if @last_sequence.to_i < sequence - 1
        raise Invalid.new("Für #{@date.year} wurde bereits die fortlaufende Nummer #{sequence - 1} verwendet. Gib mindestens diese Nummer ein.", field: :invoice_number_last)
      end
      sequence = @last_sequence.to_i + 1
    end
    if @sequence_start && sequence && !@last_sequence
      unless @sequence_start.match?(/\A[0-9]{1,9}\z/) && @sequence_start.to_i.positive?
        raise Invalid.new("Bitte gib eine ganze Zahl zwischen 1 und 999999999 ein.", field: :invoice_number_start)
      end
      automatic = sequence
      if @sequence_start.to_i < automatic
        raise Invalid.new("Der nächste Zählerstand muss mindestens #{automatic} sein, da bereits Rechnungen vergeben wurden.", field: :invoice_number_start)
      end
      sequence = @sequence_start.to_i if sequence
    end
    validate_abbreviation!(sequence)
    values["[Fortlaufendenummer]"] = sequence.to_s.rjust(4, "0") if sequence
    daily_sequence = nil
    if @format.include?("[Tageszähler]")
      pattern = @format.gsub(/\[[^\]]+\]/) { |token| values.fetch(token, token) }
      matcher = Regexp.new("\\A" + pattern.split("[Tageszähler]", -1).map { |part| Regexp.escape(part) }.join("([0-9]{2,})") + "\\z")
      used = numbers.filter_map { |existing| matcher.match(existing.to_s)&.captures&.first&.to_i }
      # A previous date-only number represents the first invoice in this series.
      legacy_base = pattern.delete_suffix("-[Tageszähler]")
      used << 1 if legacy_base != pattern && numbers.include?(legacy_base)
      daily_sequence = (used.max || 0) + 1
      values["[Tageszähler]"] = daily_sequence.to_s.rjust(2, "0")
    end
    number = @format.gsub(/\[[^\]]+\]/) { |token| values.fetch(token, token) }
    raise Invalid, "Die erzeugte Rechnungsnummer darf höchstens 100 Zeichen enthalten." if number.length > 100
    if numbers.include?(number)
      base = number
      suffix = 2
      loop do
        number = "#{base}-#{suffix.to_s.rjust(2, '0')}"
        raise Invalid, "Die Rechnungsnummer ist mit dem automatischen Zusatz länger als 100 Zeichen. Bitte kürze dein Format." if number.length > 100
        break unless numbers.include?(number)

        suffix += 1
      end
    end
    [ number, sequence, daily_sequence ]
  end

  private

  def validate_format!
    raise Invalid, "Bitte gib ein Rechnungsnummernformat ein." if @format.blank?
    raise Invalid, "Das Rechnungsnummernformat ist zu lang. Bitte kürze den festen Text oder die Anzahl der Platzhalter." if @format.gsub("[Fortlaufendenummer]", "[Nummer]").length > 80
  end

  def validate_abbreviation!(sequence)
    if @abbreviation.present? && !@abbreviation.match?(/\A[A-Z0-9][A-Z0-9_-]{0,19}\z/)
      raise Invalid.new("Verwende für das Kundenkürzel 1 bis 20 Buchstaben A–Z, Ziffern, Bindestriche oder Unterstriche.", field: :buyer_abbreviation, sequence: sequence)
    end
    if @format.include?("[Kundenkürzel]") && @abbreviation.blank?
      raise Invalid.new("Bitte ergänze das Kundenkürzel", field: :buyer_abbreviation, sequence: sequence)
    end
  end

  def next_sequence(numbers)
    year = @date.year
    recorded = @sequence_scope.where(@date_column => @date.beginning_of_year..@date.end_of_year).maximum(@sequence_column) || 0
    # Existing invoices from before custom formats keep their original numbers.
    legacy = @number_column == :invoice_number ? numbers.filter_map { |number| number&.match(/\ARE-#{year}-(\d+)\z/)&.captures&.first&.to_i }.max || 0 : 0
    [ recorded, legacy ].max + 1
  end
end
