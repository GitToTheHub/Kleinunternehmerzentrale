# Field numbers are scoped to their form section (e.g. 20/111 is income).
# Sources and year-specific line positions: official BMF EÜR forms 2025/2026.
# These are human-readable form references, not ERiC XML element names.
class EuerFields
  Field = Data.define(:key, :label, :section, :number, :line_2025, :line_2026, :effect)
  DEFINITIONS = [
    [ "income_small_details", "Davon nicht steuerbare und nach § 19 Abs. 2 UStG ausgenommene Umsätze", "20", "119", 13, 13, :info ],
    [ "income_agriculture", "Betriebseinnahmen als Land- und Forstwirt nach § 24 UStG", "20", "104", 14, 14, :income ],
    [ "expense_profession_allowance", "Betriebsausgabenpauschale für bestimmte Berufsgruppen", "25", "195", 24, 24, :expense ],
    [ "expense_vineyard", "Sachlicher Bebauungskostenrichtbetrag und Ausbaukostenrichtbeträge für Weinbaubetriebe", "25", nil, 25, 25, :expense ],
    [ "expense_forestry", "Betriebsausgabenpauschale für Forstwirte", "25", nil, 26, 26, :expense ],
    [ "expense_livestock_reserve", "Bildung Rücklage Tierbewertung bei Land- und Forstwirten", "25", nil, nil, 27, :expense ],
    [ "property_repairs_details", "In den Grundstücksaufwendungen enthaltene Erhaltungsaufwendungen", "25", "153", 42, 43, :info ],
    [ "investment_total", "Bereits berücksichtigte Beträge mit Steuerbefreiungen nach InvStG – Gesamtbetrag", "25", "263", 93, 94, :info ],
    [ "partial_income_total", "Bereits berücksichtigte Beträge zum Teileinkünfteverfahren bzw. § 8b KStG – Gesamtbetrag", "25", "261", 94, 95, :info ],
    [ "reserve_create", "Bildung von Rücklagen nach § 6c i. V. m. § 6b EStG, R 6.6 EStR", "27", "187", 99, 100, :expense ],
    [ "reserve_transfer", "Übertragung von stillen Reserven nach § 6c i. V. m. § 6b EStG, R 6.6 EStR", "27", "170", 100, 101, :expense ],
    [ "allocation_create", "Bildung von Ausgleichsposten nach § 4g EStG", "27", "191", 101, 102, :expense ],
    [ "reserve_release", "Auflösung von Rücklagen nach § 6c i. V. m. § 6b EStG, R 6.6 EStR", "27", "120", 103, 104, :income ],
    [ "allocation_release", "Auflösung von Ausgleichsposten nach § 4g EStG", "27", "125", 104, 105, :income ],

    [ "income_small", "Einnahmen als Kleinunternehmer", "20", "111", 12, 12, :income ],
    [ "income_taxable", "Umsatzsteuerpflichtige Einnahmen (netto)", "20", "112", 15, 15, :income ],
    [ "income_exempt", "Umsatzsteuerfreie / nicht steuerbare Einnahmen", "20", "103", 16, 16, :income ],
    [ "vat_collected", "Vereinnahmte Umsatzsteuer / Umsatzsteuer auf Entnahmen", "20", "140", 17, 17, :income ],
    [ "vat_refund", "Umsatzsteuererstattung vom Finanzamt", "20", "141", 18, 18, :income ],
    [ "asset_income", "Erlöse / Entnahmen aus Anlagevermögen", "20", "102", 19, 19, :income ],
    [ "vehicle_use", "Private Fahrzeugnutzung", "20", "106", 20, 20, :income ],
    [ "other_withdrawal", "Sach-, Nutzungs- und Leistungsentnahmen", "20", "108", 21, 21, :income ],
    [ "expense_goods", "Waren, Rohstoffe und Hilfsstoffe einschließlich der Nebenkosten", "25", "100", 27, 29, :expense ],
    [ "expense_services", "Bezogene Fremdleistungen", "25", "110", 29, 30, :expense ],
    [ "expense_staff", "Ausgaben für eigenes Personal (z. B. Gehälter, Löhne und Versicherungsbeiträge)", "25", "120", 30, 31, :expense ],
    [ "afa_property", "Abschreibung auf Gebäude / Grundstücksrechte", "25", "136", 31, 32, :expense ],
    [ "afa_intangible", "Abschreibung auf immaterielle Anlagegüter", "25", "131", 32, 33, :expense ],
    [ "afa_movable", "Abschreibung auf bewegliche Anlagegüter", "25", "130", 33, 34, :expense ],
    [ "afa_special", "Sonderabschreibungen", "25", "134", 34, 35, :expense ],
    [ "asset_reduction", "Herabsetzung nach § 7g Abs. 2 EStG", "25", "138", 35, 36, :expense ],
    [ "expense_gwg", "Sofortabzug für geringwertige Anlagegüter", "25", "132", 36, 37, :expense ],
    [ "pool_release", "Auflösung eines Sammelpostens", "25", "137", 37, 38, :expense ],
    [ "asset_residual", "Restbuchwert ausgeschiedener Anlagegüter", "25", "135", 38, 39, :expense ],
    [ "expense_rent", "Miete/Pacht für Geschäftsräume und betrieblich genutzte Grundstücke", "25", "150", 39, 40, :expense ],
    [ "expense_second_home", "Aufwendungen für doppelte Haushaltsführung (z. B. Miete)", "25", "152", 40, 41, :expense ],
    [ "expense_property", "Sonstige Aufwendungen für betrieblich genutzte Grundstücke (ohne Schuldzinsen und AfA)", "25", "151", 41, 42, :expense ],
    [ "expense_phone", "Aufwendungen für Telekommunikation (z. B. Telefon, Internet)", "25", "280", 43, 44, :expense ],
    [ "expense_travel", "Übernachtungs- und Reisenebenkosten bei Geschäftsreisen des Steuerpflichtigen", "25", "221", 44, 45, :expense ],
    [ "expense_training", "Fortbildungskosten (ohne Reisekosten)", "25", "281", 45, 46, :expense ],
    [ "expense_advice", "Kosten für Rechts- und Steuerberatung, Buchführung", "25", "194", 46, 47, :expense ],
    [ "expense_leasing", "Miete/Leasing für bewegliche Wirtschaftsgüter (ohne Kfz)", "25", "222", 47, 48, :expense ],
    [ "expense_repairs", "Erhaltungsaufwendungen (z. B. Instandhaltung, Wartung, Reparatur; ohne solche für Gebäude und Kfz)", "25", "225", 48, 49, :expense ],
    [ "expense_insurance", "Beiträge, Gebühren, Abgaben und Versicherungen (ohne solche für Gebäude und Kfz)", "25", "223", 49, 50, :expense ],
    [ "expense_it", "Laufende EDV-Kosten (z. B. Beratung, Wartung, Reparatur)", "25", "228", 50, 51, :expense ],
    [ "expense_supplies", "Arbeitsmittel (z. B. Bürobedarf, Porto, Fachliteratur)", "25", "229", 51, 52, :expense ],
    [ "expense_waste", "Kosten für Abfallbeseitigung und Entsorgung", "25", "226", 52, 53, :expense ],
    [ "expense_transport", "Kosten für Verpackung und Transport", "25", "227", 53, 54, :expense ],
    [ "expense_advertising", "Werbekosten (z. B. Inserate, Werbespots, Plakate)", "25", "224", 54, 55, :expense ],
    [ "expense_asset_interest", "Schuldzinsen zur Finanzierung von Anschaffungs- und Herstellungskosten von Wirtschaftsgütern des Anlagevermögens (ohne häusliches Arbeitszimmer)", "25", "232", 55, 56, :expense ],
    [ "expense_interest", "Übrige Schuldzinsen", "25", "234", 56, 57, :expense ],
    [ "input_vat", "Gezahlte abziehbare Vorsteuer", "25", "185", 57, 58, :expense ],
    [ "vat_payment", "Umsatzsteuerzahlung an das Finanzamt", "25", "186", 58, 59, :expense ],
    [ "expense_other", "Übrige unbeschränkt abziehbare Betriebsausgaben", "25", "183", 60, 61, :expense ],
    [ "expense_gifts", "Geschenke – abziehbarer Anteil", "25", "174", 62, 63, :expense ],
    [ "gifts_disallowed", "Geschenke – nicht abziehbarer Anteil", "25", "164", 62, 63, :info ],
    [ "expense_meals", "Geschäftliche Bewirtung – abziehbarer Anteil", "25", "175", 63, 64, :expense ],
    [ "meals_disallowed", "Bewirtung – nicht abziehbarer Anteil", "25", "165", 63, 64, :info ],
    [ "expense_meal_allowance", "Verpflegungspauschalen", "25", "171", 64, 65, :expense ],
    [ "expense_home_office", "Arbeitszimmer – abziehbarer Anteil", "25", "172", 65, 66, :expense ],
    [ "home_office_disallowed", "Arbeitszimmer – nicht abziehbarer Anteil", "25", "162", 65, 66, :info ],
    [ "expense_home_days", "Tagespauschale für Arbeit zuhause", "25", "163", 66, 67, :expense ],
    [ "expense_limited", "Sonstige beschränkte Ausgaben – abziehbarer Anteil", "25", "177", 67, 68, :expense ],
    [ "limited_disallowed", "Sonstige beschränkte Ausgaben – nicht abziehbarer Anteil", "25", "168", 67, 68, :info ],
    [ "expense_vehicle_leasing", "Fahrzeugleasing", "25", "144", 68, 69, :expense ],
    [ "expense_vehicle_tax", "Fahrzeugsteuer, Versicherung und Maut", "25", "145", 69, 70, :expense ],
    [ "expense_vehicle", "Fahrzeug- und Fahrtkosten", "25", "146", 70, 71, :expense ],
    [ "expense_private_vehicle", "Betriebliche Fahrten mit Privatfahrzeug", "25", "147", 71, 72, :expense ],
    [ "commute_reduction", "Kürzung für Fahrten zur Betriebsstätte", "25", "142", 72, 73, :expense_reduction ],
    [ "expense_commute", "Entfernungspauschale", "25", "176", 73, 74, :expense ],
    [ "expense_disallowed", "Weitere nicht abziehbare Beträge", "25", "139", 74, 75, :expense_reduction ],
    [ "tax_exempt_allowance", "Steuerfreie Einnahmen nach § 3 Nr. 26 / 26a / 26b", "25", "240", 78, 79, :profit_minus ],
    [ "tax_exempt_other", "Weitere steuerfreie Einnahmen nach § 3", "25", "241", 79, 80, :profit_minus ],
    [ "tax_exempt_restructuring", "Steuerfreier Sanierungsertrag", "25", "242", 80, 81, :profit_minus ],
    [ "tax_add_allowance", "Nicht abziehbare Ausgaben zu § 3 Nr. 26 / 26a / 26b", "25", "243", 81, 82, :profit_plus ],
    [ "tax_add_exempt", "Nicht abziehbare Ausgaben nach § 3c Abs. 1", "25", "244", 82, 83, :profit_plus ],
    [ "tax_add_restructuring", "Nicht abziehbare Ausgaben nach § 3c Abs. 4", "25", "245", 83, 84, :profit_plus ],
    [ "iab_add_3", "Hinzurechnung Investitionsabzug aus dem drittvorigen Jahr", "25", "180", 84, 85, :profit_plus ],
    [ "iab_add_2", "Hinzurechnung Investitionsabzug aus dem zweitvorigen Jahr", "25", "181", 85, 86, :profit_plus ],
    [ "iab_add_1", "Hinzurechnung Investitionsabzug aus dem Vorjahr", "25", "182", 86, 87, :profit_plus ],
    [ "reserve_profit", "Gewinnzuschlag nach § 6b / § 6c", "25", "123", 87, 88, :profit_plus ],
    [ "iab_deduction", "Investitionsabzugsbetrag nach § 7g Abs. 1", "25", "187", 88, 89, :profit_minus ],
    [ "method_change", "Übergangsgewinn / Übergangsverlust", "25", "250", 89, 90, :profit_plus ],
    [ "partnership_result", "Ergebnisanteile aus Beteiligungen", "25", "255", 91, 92, :profit_plus ],
    [ "investment_correction", "Korrektur nach Investmentsteuergesetz", "25", "264", 93, 94, :profit_plus ],
    [ "partial_income_correction", "Korrektur nach Teileinkünfteverfahren", "25", "262", 94, 95, :profit_plus ],
    [ "interest_addback", "Nicht abziehbare Schuldzinsen nach § 4 Abs. 4a", "25", "271", 96, 97, :profit_plus ],
    [ "withdrawals", "Entnahmen einschließlich Sach- und Nutzungsentnahmen", "29", "122", 106, 107, :info ],
    [ "deposits", "Einlagen einschließlich Sacheinlagen", "29", "123", 107, 108, :info ]
  ].map { |args| Field.new(*args) }.index_by(&:key).freeze

  # Kleinunternehmer erfassen Gesamtbeträge ohne Vorsteuerabzug.
  REGULAR_TAX_KEYS = %w[income_taxable income_exempt vat_collected input_vat].freeze
  SPECIAL_VAT_KEYS = %w[vat_payment vat_refund].freeze

  def self.fields_for(year)
    DEFINITIONS.values.select { |field| line(field.key, year) }.sort_by { |field| [ line(field.key, year), field.number.to_s ] }
  end

  def self.small_business?(key) = !REGULAR_TAX_KEYS.include?(key)

  def self.small_business_fields
    DEFINITIONS.values.reject { |field| REGULAR_TAX_KEYS.include?(field.key) }
  end

  def self.selection_label(key)
    label = DEFINITIONS.fetch(key).label
    SPECIAL_VAT_KEYS.include?(key) ? "#{label} (Sonderfall für Kleinunternehmer)" : label
  end

  SOURCES = {
    2025 => "https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Einkommensteuer/2025-08-29-anlage-EUER-2025.pdf?__blob=publicationFile&v=3",
    2026 => "https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Einkommensteuer/2026-09-01-anlage-EUER-2026.pdf?__blob=publicationFile&v=4"
  }.freeze

  def self.source_note(year)
    if supported?(year)
      "Formulargrundlage: amtliche Anlage EÜR #{year}."
    else
      "Für #{year} liegen in der App keine amtlich geprüften Formulardaten vor. Es wird keine Zuordnung aus einem anderen Jahr als gültig für #{year} ausgegeben."
    end
  end

  def self.supported?(year) = SOURCES.key?(year)

  def self.line(key, year)
    return unless supported?(year)

    DEFINITIONS.fetch(key).public_send("line_#{year}")
  end
end
