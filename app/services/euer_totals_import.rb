require "csv"

class EuerTotalsImport
  class InvalidFile < StandardError; end
  MAX_BYTES = 1.megabyte
  POSITION_HEADERS = [ "position", "eür-position", "euer-position", "kategorie" ].freeze
  AMOUNT_HEADERS = [ "betrag", "betrag_eur", "betrag eur", "betrag in euro" ].freeze

  def self.parse_amount(value)
    text = value.to_s.strip.delete_suffix("€").strip
    return nil if text.blank?

    if text.include?(",")
      raise InvalidFile, "Ungültiger Betrag: #{text}" unless text.match?(/\A-?(?:\d+|\d{1,3}(?:\.\d{3})+),\d{1,2}\z/)

      text = text.delete(".").tr(",", ".")
    end
    raise InvalidFile, "Ungültiger Betrag: #{text}" unless text.match?(/\A-?\d+(?:\.\d{1,2})?\z/) && text.to_d.abs < 10_000_000_000

    text.to_d.to_s("F")
  end

  def self.resolve_position(value)
    text = value.to_s.strip
    field = EuerFields::DEFINITIONS.values.find { |candidate| candidate.key == text || candidate.label.casecmp?(text) || EuerFields.selection_label(candidate.key).casecmp?(text) || EuerFields::SOURCES.keys.any? { |year| EuerFields.line(candidate.key, year) && EuerFormLabels.label(candidate.key, year).casecmp?(text) } }
    raise InvalidFile, "Unbekannte EÜR-Position „#{text}“. Nutze die Positionsschlüssel aus der Vorlage; Summen wie Gewinn oder Gesamtausgaben sind keine eigenen Positionen." unless field

    field.key
  end

  def self.manual(values)
    values.to_h.each_with_object({}) do |(key, value), amounts|
      next if value.to_s.strip.blank?

      position = resolve_position(key)
      amount = parse_amount(value)
      amounts[position] = amount unless amount.to_d.zero?
    end
  end

  def self.csv(upload)
    raise InvalidFile, "Die CSV-Datei darf höchstens 1 MB groß sein." if upload.size > MAX_BYTES

    raw = upload.read(MAX_BYTES + 1)
    raise InvalidFile, "Die CSV-Datei darf höchstens 1 MB groß sein." if raw.bytesize > MAX_BYTES

    raw = raw.force_encoding(Encoding::UTF_8)
    raw = raw.force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8) unless raw.valid_encoding?
    raw = raw.delete_prefix("\uFEFF")
    if raw.start_with?("EXTF", '"EXTF"', "DTVF", '"DTVF"')
      raise InvalidFile, "Dies ist ein DATEV-Buchungsstapel, keine EÜR-Summenliste. Übertrage die geprüften EÜR-Positionen in die CSV-Vorlage oder erfasse die Summen direkt."
    end
    separator = raw.lines.first.to_s.include?(";") ? ";" : ","
    table = CSV.parse(raw, headers: true, col_sep: separator, field_size_limit: 10_000)
    headers = Array(table.headers).map { |header| header.to_s.strip.downcase }
    position_index = headers.index { |header| POSITION_HEADERS.include?(header) }
    amount_index = headers.index { |header| AMOUNT_HEADERS.include?(header) }
    raise InvalidFile, "Die CSV braucht die Spalten „Position“ und „Betrag“. Lade bei Bedarf die Vorlage herunter." unless position_index && amount_index
    raise InvalidFile, "Die CSV darf höchstens 200 Positionen enthalten." if table.size > 200

    table.each_with_index.each_with_object({}) do |(row, index), amounts|
      next if row.fields.all? { |value| value.to_s.strip.blank? }

      begin
        position = resolve_position(row[position_index])
        raise InvalidFile, "Position mehrfach vorhanden: #{position}" if amounts.key?(position)

        amount = parse_amount(row[amount_index])
        raise InvalidFile, "Betrag fehlt." if amount.nil?

        amounts[position] = amount
      rescue InvalidFile => error
        raise InvalidFile, "Zeile #{index + 2}: #{error.message}"
      end
    end.reject { |_, amount| amount.to_d.zero? }
  rescue CSV::MalformedCSVError, EncodingError, ArgumentError => error
    raise InvalidFile, "Die CSV-Datei konnte nicht gelesen werden: #{error.message}"
  end

  def self.template
    "\uFEFF" + CSV.generate(col_sep: ";") do |csv|
      csv << %w[Position Betrag Beschreibung]
      EuerFields::DEFINITIONS.values.each { |field| csv << [ field.key, "0,00", field.label ] }
    end
  end
end
