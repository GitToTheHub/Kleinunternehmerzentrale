# Monthly periods use anonymous child/place labels. No children's personal data
# is needed. Based on BMF 06.04.2023, paragraphs 9–17, checked with EÜR 2025/2026.
class EuerDaycareAllowance
  KEYS = %w[label start_month end_month kind weekly_hours daily_hours occupied_days].freeze
  RULES = {
    2025 => { child: 400, reserved: 50, weekly_hours: 40, daily_hours: 8, days: 20 }.freeze,
    2026 => { child: 400, reserved: 50, weekly_hours: 40, daily_hours: 8, days: 20 }.freeze
  }.freeze

  def initialize(rows, year)
    @rows, @year = rows, year
  end

  def errors
    return [ "Für dieses Jahr fehlt eine geprüfte Kindertagespflege-Pauschale." ] unless RULES.key?(@year)
    return [ "Erfasse mindestens einen Betreuungszeitraum." ] unless @rows.is_a?(Array) && @rows.any? && @rows.size <= 500

    occupied = []
    @rows.each_with_index.filter_map do |row, index|
      next "Betreuungszeitraum #{index + 1} enthält unbekannte Angaben." unless row.is_a?(Hash) && (row.keys - KEYS).empty?

      label = row["label"].to_s.strip
      first, last = integer(row["start_month"]), integer(row["end_month"])
      next "Betreuungszeitraum #{index + 1}: Kürzel und Monate von 1 bis 12 mit Ende nach Beginn angeben." unless label.present? && label.length <= 80 && first&.between?(1, 12) && last&.between?(first, 12)

      months = (first..last).map { |month| [ label.downcase, month ] }
      next "Die Zeiträume für #{label} überschneiden sich. Pro Kind oder Freihalteplatz und Monat nur einen Datensatz verwenden." if (occupied & months).any?

      occupied.concat(months)
      if row["kind"] == "regular"
        hours = decimal(row["weekly_hours"])
        "Betreuungszeitraum #{index + 1}: Gültige Wochenstunden zwischen 0 und 168 angeben." unless hours && hours.positive? && hours <= 168
      elsif row["kind"] == "reserved"
        days = integer(row["occupied_days"])
        hours = decimal(row["daily_hours"])
        "Freihalteplatz #{index + 1}: Belegte Tage von 0 bis 20 und bei Belegung gültige Tagesstunden bis 24 angeben." unless days&.between?(0, 20) && (days.zero? || (hours && hours.positive? && hours <= 24))
      else
        "Betreuungszeitraum #{index + 1}: Betreuung oder Freihalteplatz auswählen."
      end
    end
  end

  def amount
    return 0.to_d if errors.any?

    rules = RULES.fetch(@year)
    @rows.sum do |row|
      months = integer(row["end_month"]) - integer(row["start_month"]) + 1
      monthly = if row["kind"] == "regular"
        rules[:child].to_d * [ decimal(row["weekly_hours"]), rules[:weekly_hours] ].min / rules[:weekly_hours]
      else
        days = integer(row["occupied_days"])
        reserve = rules[:reserved].to_d * (rules[:days] - days) / rules[:days]
        care = days.zero? ? 0.to_d : rules[:child].to_d * [ decimal(row["daily_hours"]), rules[:daily_hours] ].min / rules[:daily_hours] * days / rules[:days]
        reserve + care
      end
      monthly * months
    end.round(2)
  end

  private

  def integer(value)
    Integer(value.to_s, 10, exception: false) if value.to_s.match?(/\A\d+\z/)
  end

  def decimal(value)
    string = value.to_s.strip.tr(",", ".")
    BigDecimal(string) if string.match?(/\A\d+(?:\.\d{1,2})?\z/)
  end
end
