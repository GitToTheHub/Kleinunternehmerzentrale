# Complete main Anlage EÜR (four pages), separate from its supplementary forms.
class EuerForm
  Row = Data.define(:line, :key, :label, :kind, :number)
  DETAILS = {
    "taxpayer_name" => [ 1, "Name des Steuerpflichtigen bzw. der Gesellschaft/Gemeinschaft/Körperschaft", :text ],
    "first_name" => [ 2, "Vorname", :text ],
    "tax_number" => [ 3, "(Betriebs-)Steuernummer", :text ],
    "period_start" => [ 4, "Vom Kalenderjahr abweichender Beginn", :date ],
    "period_end" => [ 4, "Vom Kalenderjahr abweichendes Ende", :date ],
    "business_id" => [ 5, "Wirtschafts-Identifikationsnummer", :text ],
    "activity" => [ 6, "Art des Betriebs", :text ],
    "legal_form" => [ 7, "Rechtsform des Betriebs", :text ],
    "income_type" => [ 8, "Einkunftsart", { "1" => "Land- und Forstwirtschaft", "2" => "Gewerbebetrieb", "3" => "Selbständige Arbeit" } ],
    "owner" => [ 9, "Betriebsinhaber", { "1" => "Steuerpflichtige Person / Person A / Gesellschaft / Körperschaft", "2" => "Person B", "3" => "Beide Ehegatten / Lebenspartner" } ],
    "termination" => [ 10, "Wurde im Kalenderjahr/Wirtschaftsjahr der Betrieb beendet?", { "1" => "Veräußert oder Aufgabe", "2" => "Unentgeltliche Übertragung" } ],
    "property_disposal" => [ 11, "Wurden Grundstücke/grundstücksgleiche Rechte entnommen oder veräußert?", { "1" => "Ja", "2" => "Nein" } ]
  }.freeze
  COMPUTED = [
    [ 22, 22, "reserve_income_total", "Auflösung von Rücklagen und/oder Ausgleichsposten", nil ],
    [ 23, 23, "income_total", "Summe Betriebseinnahmen", "159" ],
    [ 28, 28, "first_expense_carry", "Übertrag (Summe Zeilen 24 bis 27)", nil ],
    [ 59, 60, "reserve_expense_total", "Rücklagen, stille Reserven und/oder Ausgleichsposten", nil ],
    [ 61, 62, "expense_carry", "Übertrag der bisherigen Betriebsausgaben", nil ],
    [ 75, 76, "expenses_total", "Summe Betriebsausgaben", "199" ],
    [ 76, 77, "income_repeat", "Summe der Betriebseinnahmen", nil ],
    [ 77, 78, "expenses_repeat", "abzüglich Summe der Betriebsausgaben", nil ],
    [ 90, 91, "profit_carry", "Übertrag (Summe/Differenz der Gewinnermittlung)", nil ],
    [ 92, 93, "corrected_profit", "Korrigierter Gewinn/Verlust", "290" ],
    [ 95, 96, "profit_before_interest", "Steuerpflichtiger Gewinn/Verlust vor Anwendung des § 4 Abs. 4a EStG", "293" ],
    [ 97, 98, "profit_total", "Steuerpflichtiger Gewinn/Verlust", "219" ],
    [ 98, 99, "partnership_profit", "Nur bei Personengesellschaften/gesonderten Feststellungen: Anzusetzender steuerpflichtiger Gewinn/Verlust nach Anwendung des § 4 Abs. 4a EStG ohne Berücksichtigung des InvStG, des Teileinkünfteverfahrens bzw. § 8b KStG", nil ],
    [ 102, 103, "reserve_creation_total", "Gesamtsumme Bildung/Übertragung von Rücklagen, stillen Reserven und Ausgleichsposten", "190" ],
    [ 105, 106, "reserve_release_total", "Gesamtsumme Auflösung von Rücklagen und Ausgleichsposten", "124" ]
  ].freeze

  def self.rows(year)
    return [] unless EuerFields.supported?(year)

    fields = EuerFields.fields_for(year).map { |field| Row.new(EuerFields.line(field.key, year), field.key, EuerFormLabels.label(field.key, year), :amount, field.number) }
    details = DETAILS.map { |key, (line, label, _)| Row.new(line, key, label, :detail, nil) }
    computed = COMPUTED.map { |line_2025, line_2026, key, label, number| Row.new(year == 2025 ? line_2025 : line_2026, key, computed_label(key, label, year), :computed, number) }
    (fields + details + computed).sort_by { |row| [ row.line, row.number.to_s, row.key ] }
  end

  def self.computed_label(key, label, year)
    case key
    when "reserve_income_total" then "#{label} (Übertrag aus Zeile #{year == 2025 ? 105 : 106})"
    when "income_total" then "#{label} (Übertrag in Zeile #{year == 2025 ? 76 : 77})"
    when "reserve_expense_total" then "#{label} (Übertrag aus Zeile #{year == 2025 ? 102 : 103})"
    when "expense_carry" then "Übertrag (Summe Zeilen 24 bis 27 und Zeilen 29 bis #{year == 2025 ? 60 : 61})"
    when "expenses_total" then "#{label} (Übertrag in Zeile #{year == 2025 ? 77 : 78})"
    when "income_repeat" then "#{label} (Übertrag aus Zeile 23)"
    when "expenses_repeat" then "#{label} (Übertrag aus Zeile #{year == 2025 ? 75 : 76})"
    when "profit_carry" then "Übertrag (Summe/Differenz Zeilen #{year == 2025 ? '76 bis 89' : '77 bis 90'})"
    when "partnership_profit" then "#{label} (Betrag lt. Zeile #{year == 2025 ? 92 : 93} zuzüglich Betrag lt. Zeile #{year == 2025 ? 96 : 97})"
    when "reserve_creation_total" then "#{label} (Übertrag in Zeile #{year == 2025 ? 59 : 60})"
    when "reserve_release_total" then "#{label} (Übertrag in Zeile 22)"
    else label
    end
  end

  def self.amount(key, report)
    values = report.field_totals
    return values.fetch(key) if EuerFields::DEFINITIONS.key?(key)

    reserve_expenses = %w[reserve_create reserve_transfer allocation_create].sum { |field| values.fetch(field) }
    reserve_income = %w[reserve_release allocation_release].sum { |field| values.fetch(field) }
    corrected = report.surplus - values.fetch("investment_correction") - values.fetch("partial_income_correction") - values.fetch("interest_addback")
    case key
    when "reserve_income_total", "reserve_release_total" then reserve_income
    when "reserve_expense_total", "reserve_creation_total" then reserve_expenses
    when "income_total", "income_repeat" then report.income
    when "expenses_total", "expenses_repeat" then report.expenses
    when "first_expense_carry", "expense_carry"
      last_line = key == "first_expense_carry" ? 27 : (report.year == 2025 ? 60 : 61)
      total = EuerFields.fields_for(report.year).select { |field| field.effect == :expense && (24..last_line).cover?(EuerFields.line(field.key, report.year)) }.sum { |field| values.fetch(field.key) }
      key == "expense_carry" ? total + reserve_expenses : total
    when "profit_carry" then corrected - values.fetch("partnership_result")
    when "corrected_profit" then corrected
    when "profit_before_interest" then report.surplus - values.fetch("interest_addback")
    when "profit_total" then report.surplus
    when "partnership_profit" then corrected + values.fetch("interest_addback")
    else raise KeyError, key
    end
  end
end
