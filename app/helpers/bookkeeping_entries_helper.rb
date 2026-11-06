module BookkeepingEntriesHelper
  def bookkeeping_amount_input(entry)
    raw = entry.amount_before_type_cast
    return raw if raw.blank? || entry.errors[:amount].any?

    number_with_precision(entry.amount, precision: 2, separator: ",", delimiter: "")
  end

  BOOKING_ICON_PATHS = {
    "business" => "M3 7h18v14H3ZM8 7V3h8v4M3 12h18M10 12v3h4v-3",
    "private_money" => "M9 7a3 3 0 1 0 6 0 3 3 0 0 0-6 0M5 21v-3a7 7 0 0 1 14 0v3M3 10v5m-2-2 2 2 2-2M21 15v-5m-2 2 2-2 2 2",
    "noncash" => "m3 7 9-4 9 4-9 4ZM3 7v10l9 4 9-4V7M12 11v10M7 5l10 4",
    "income" => "M12 3v11m-4-4 4 4 4-4M4 15v6h16v-6",
    "expense" => "M12 14V3m-4 4 4-4 4 4M4 15v6h16v-6",
    "deposit" => "M3 6h17v15H3ZM3 6V3h14v3M16 11v5m-2-2.5h4",
    "withdrawal" => "M3 6h17v15H3ZM3 6V3h14v3M14 13.5h4",
    "noncash_deposit" => "m3 7 9-4 9 4-9 4ZM3 7v10l9 4 9-4V7M12 11v10M16 14v4m-2-2h4",
    "noncash_withdrawal" => "m3 7 9-4 9 4-9 4ZM3 7v10l9 4 9-4V7M12 11v10M14 16h4"
  }.freeze

  def bookkeeping_icon(key)
    content_tag(:svg, tag.path(d: BOOKING_ICON_PATHS.fetch(key.to_s)),
      class: "booking-category-icon", viewBox: "0 0 24 24", fill: "none", stroke: "currentColor",
      "stroke-width" => 1.6, "stroke-linecap" => "round", "stroke-linejoin" => "round",
      "aria-hidden" => true, focusable: false)
  end

  BOOKING_GROUPS = {
    "business" => { title: "Betriebliche Einnahmen und Ausgaben", hint: "Zahlungen von Kunden und bezahlte Kosten für deinen Betrieb.", kinds: %w[income expense] },
    "private_money" => { title: "Zwischen Privat und Betrieb", hint: "Hier geht es um Geld und Gegenstände, die zwischen dir als Privatperson und deinem Betrieb wechseln. Wähle, ob du Geld oder eine Sache einbringst oder privat entnimmst.", kinds: %w[deposit withdrawal noncash_deposit noncash_withdrawal] }
  }.freeze

  BOOKING_ACTIONS = {
    "income" => { title: "Einnahmen", button: "Einnahme erfassen",
      hint: "Geld, das du für Leistungen oder Waren deines Betriebs tatsächlich erhalten hast.",
      example: "Ein Kunde bezahlt deine Rechnung.",
      detail: "Auch Kundenzahlungen auf dein Privatkonto und Barzahlungen sind Betriebseinnahmen. Wähle unter „Zahlungsart“, wie du das Geld erhalten hast." },
    "expense" => { title: "Ausgaben", button: "Ausgabe erfassen",
      hint: "Kosten für deinen Betrieb, die du bezahlt hast. Das gilt auch, wenn du vom Privatkonto bezahlt hast.",
      example: "Du bezahlst ein Software-Abo oder deine betriebliche Telefonrechnung.",
      detail: "Wähle bei privater Zahlung „Privatkonto / privat bezahlt“. Die App berücksichtigt die zugehörige Einlage automatisch; erfasse dafür keine zweite Geldeinlage. Länger genutzte Ausstattung wie Computer erfasst du über „Anlagegut erfassen“." },
    "deposit" => { title: "Private Geldeinlagen", button: "Geldeinlage erfassen",
      hint: "Du überträgst eigenes Geld aus deinem privaten Bereich auf dein Betriebskonto oder in die betriebliche Kasse.",
      example: "Du überweist 300 Euro vom Privatkonto auf dein Betriebskonto.",
      detail: "Bezahlst du stattdessen eine betriebliche Rechnung direkt vom Privatkonto, erfasse eine Betriebsausgabe mit „Privatkonto / privat bezahlt“. Die App berücksichtigt die Einlage dann automatisch." },
    "withdrawal" => { title: "Private Geldentnahmen", button: "Geldentnahme erfassen",
      hint: "Du nimmst Geld aus deinem Betrieb für private Zwecke oder bezahlst eine private Rechnung vom Betriebskonto.",
      example: "Du überweist 200 Euro vom Betriebskonto auf dein Privatkonto.",
      detail: "Eine Kundenzahlung auf dein Privatkonto erfasst du dagegen als Betriebseinnahme. Die App berücksichtigt die zugehörige Geldentnahme automatisch. Rein private Zahlungen auf deinem Privatkonto lässt du weg." },
    "noncash_deposit" => { title: "Sacheinlagen", button: "Sacheinlage erfassen",
      hint: "Du übernimmst einen bisher privaten Gegenstand in deinen Betrieb. Hier erfasst du private Waren und Verbrauchsmaterial.",
      detail: "Ein bisher privater Mac kann ebenfalls eine Sacheinlage sein. Erfasse ihn als Anlagegut mit dem Zugang „Aus Privatvermögen eingelegt“, nicht zusätzlich hier. Ein neuer betrieblicher Kauf vom Privatkonto ist eine Anschaffung mit privater Zahlung. Einen privaten Gegenstand nur gelegentlich beruflich zu nutzen, bedeutet noch nicht automatisch, ihn ins Betriebsvermögen zu übernehmen." },
    "noncash_withdrawal" => { title: "Sach-, Nutzungs- und Leistungsentnahmen", button: "Sach-, Nutzungs- oder Leistungsentnahme erfassen",
      hint: "Du entnimmst Waren für private Zwecke oder nutzt betriebliche Gegenstände und Leistungen privat. Dabei fließt kein Geld.",
      example: "Sachentnahme: Ware für dich selbst mitnehmen. Nutzungsentnahme: eine betriebliche Maschine privat nutzen. Leistungsentnahme: Ein Mitarbeiter streicht während seiner bezahlten Arbeitszeit deine private Wohnung.",
      detail: "Bei einer Nutzungsentnahme bleibt der Gegenstand im Betrieb. Bei einer Leistungsentnahme nutzt du betriebliche Leistungen für private Zwecke. Trage den steuerlich ermittelten Wert ein. Die private Nutzung eines Anlageguts kannst du auch direkt beim Anlagegut verwalten. Erfasse denselben Wert nur einmal. Eine dauerhafte Privatentnahme eines Anlageguts erfasst du direkt im Anlageverzeichnis." }
  }.freeze

  EXPENSE_GROUPS = {
    "Telefon, Internet und EDV" => %w[expense_phone expense_it],
    "Büro und Räume" => %w[expense_supplies expense_rent expense_second_home expense_property expense_home_office],
    "Ausstattung, Miete und Reparaturen" => %w[expense_leasing expense_repairs],
    "Personal, Dienstleistungen und Weiterbildung" => %w[expense_staff expense_services expense_advice expense_training],
    "Fahrzeuge und Reisen" => %w[expense_travel expense_vehicle_leasing expense_vehicle_tax expense_vehicle],
    "Werbung, Bewirtung und Geschenke" => %w[expense_advertising expense_meals expense_gifts],
    "Waren, Versand und Entsorgung" => %w[expense_goods expense_transport expense_waste],
    "Versicherungen, Finanzierung und Steuern" => %w[expense_insurance expense_asset_interest expense_interest input_vat vat_payment],
    "Sonstige Betriebsausgaben" => %w[expense_other expense_limited]
  }.freeze

  def bookkeeping_expense_group(key)
    EXPENSE_GROUPS.find { |_, keys| keys.include?(key) }&.first || "Sonstige Betriebsausgaben"
  end

  EXPENSE_EXAMPLES = {
    "expense_phone" => "Mobilfunkvertrag oder Internetanschluss",
    "expense_it" => "Software-Abos, Hosting oder Cloud-Speicher",
    "expense_supplies" => "Papier, Stifte oder Druckerpatronen",
    "expense_rent" => "Büromiete, Ladenmiete oder Coworking-Platz",
    "expense_second_home" => "Unterkunft im Rahmen einer betrieblichen doppelten Haushaltsführung",
    "expense_property" => "Strom, Heizung oder Reinigung für Geschäftsräume",
    "expense_home_office" => "Kosten eines steuerlich anerkannten häuslichen Arbeitszimmers",
    "expense_leasing" => "Miete einer Maschine oder eines Arbeitsgeräts",
    "expense_repairs" => "Wartung einer Maschine oder Reparatur eines Computers",
    "expense_staff" => "Gehälter, Löhne oder Arbeitgeberbeiträge",
    "expense_services" => "Leistungen von Subunternehmern oder anderen Selbstständigen",
    "expense_advice" => "Steuerberatung, Rechtsberatung oder Buchführung",
    "expense_training" => "Beruflicher Kurs, Seminar oder Schulung",
    "expense_travel" => "Hotelübernachtung auf einer Geschäftsreise",
    "expense_vehicle_leasing" => "Leasingrate für ein betriebliches Fahrzeug",
    "expense_vehicle_tax" => "Kfz-Steuer, Fahrzeugversicherung oder Maut",
    "expense_vehicle" => "Treibstoff, Fahrzeugreparatur oder betriebliches Bahnticket",
    "expense_advertising" => "Anzeigen, Werbeflyer oder Visitenkarten",
    "expense_meals" => "Geschäftsessen mit Kunden; besondere Abzugsregeln beachten",
    "expense_gifts" => "Kundengeschenke; besondere Abzugsregeln beachten",
    "expense_goods" => "Handelsware, Rohstoffe oder Material zur Verarbeitung",
    "expense_transport" => "Versandkartons, Paketversand oder Spedition",
    "expense_waste" => "Betriebliche Müllabfuhr oder Abfallentsorgung",
    "expense_insurance" => "Betriebshaftpflicht, Kammerbeitrag oder Geräteversicherung",
    "expense_asset_interest" => "Zinsen für einen Investitionskredit",
    "expense_interest" => "Zinsen für einen betrieblichen Betriebsmittelkredit",
    "input_vat" => "Abziehbare Vorsteuer; für Kleinunternehmer regelmäßig nicht anwendbar",
    "vat_payment" => "Umsatzsteuer ans Finanzamt, etwa bei Reverse Charge",
    "expense_other" => "Kontoführungsgebühren oder weitere nicht gesondert zugeordnete Kosten",
    "expense_limited" => "Sonstige Ausgaben mit steuerlich begrenztem Abzug"
  }.freeze

  def bookkeeping_kind_label(kind)
    return BOOKING_ACTIONS.fetch(kind).fetch(:title) if kind.start_with?("noncash_")

    BookkeepingEntry::KINDS.fetch(kind)
  end

  def bookkeeping_form_categories(entry)
    keys = BookkeepingEntry::SMALL_BUSINESS_CATEGORIES.values.flatten.uniq
    keys |= [ entry.effective_category ].compact if entry.persisted?
    keys
  end

  def bookkeeping_category_label(key, _year = nil)
    return EuerFields.selection_label(key) if BookkeepingEntry::EXPENSE_CATEGORIES.include?(key)

    EVERYDAY_CATEGORIES.fetch(key, EuerFields.selection_label(key))
  end

  EVERYDAY_CATEGORIES = {
    "income_small" => "Geld von Kunden für Leistungen oder Waren",
    "expense_phone" => "Telefon und Internet – zum Beispiel Mobilfunkvertrag",
    "expense_it" => "Software und Online-Dienste – zum Beispiel Lizenzen oder Hosting",
    "expense_supplies" => "Büromaterial – zum Beispiel Papier oder Stifte",
    "expense_goods" => "Waren und Material zum Weiterverkaufen oder Verarbeiten",
    "expense_services" => "Leistungen anderer Selbstständiger",
    "expense_training" => "Kurse, Fachbücher und Weiterbildung",
    "expense_advertising" => "Werbung und Anzeigen",
    "expense_repairs" => "Wartung und Reparaturen",
    "expense_other" => "Sonstige laufende Kosten – bitte beschreiben"
  }.freeze

  CATEGORY_HELP = {
    "income_small" => {
      explanation: "Für deine normalen Einnahmen als Kleinunternehmer: Geld, das Kunden für deine Leistungen oder Waren bezahlen.",
      example: "Beispiel: Ein Kunde bezahlt deine Rechnung für eine Beratung."
    },
    "vat_refund" => {
      explanation: "Diese Kategorie brauchst du als Kleinunternehmer meist nicht. Wähle sie nur, wenn das Finanzamt dir ausdrücklich betriebliche Umsatzsteuer zurückerstattet oder gutschreibt. Eine Einkommensteuererstattung gehört nicht in die EÜR.",
      example: "Beispiel: Du hast wegen einer Dienstleistung aus dem Ausland Umsatzsteuer ans Finanzamt gezahlt. Nach einer Korrektur bekommst du zu viel gezahlte Umsatzsteuer zurück. Eine Rückzahlung des Anbieters korrigiert dagegen die ursprüngliche Ausgabe."
    },
    "vat_payment" => {
      explanation: "Nur für Sonderfälle: Umsatzsteuer, die du selbst an das Finanzamt zahlst. Die Umsatzsteuer auf einer normalen Einkaufsrechnung gehört zum Gesamtbetrag deiner Ausgabe und wird hier nicht zusätzlich erfasst.",
      example: "Beispiel: Bei einer betrieblichen Dienstleistung aus dem Ausland kann die Pflicht zur Zahlung der deutschen Umsatzsteuer auf dich übergehen (Reverse Charge), auch als Kleinunternehmer."
    },
    "asset_income" => {
      explanation: "Anlagevermögen sind Dinge, die du länger für deinen Betrieb nutzt, zum Beispiel ein Computer, eine Maschine oder ein Firmenfahrzeug. Wähle diese Kategorie, wenn du solche Gegenstände verkaufst. „Erlös“ bedeutet das Geld, das du dafür erhältst.",
      example: "Beispiel: Du verkaufst deinen betrieblichen Computer für 300 €. Erfasse die erhaltenen 300 € hier und trage den Verkauf auch beim Computer im Anlageverzeichnis ein. Buche den Zahlungseingang nur einmal und nicht zusätzlich als normale Einnahme.",
      assets: true
    },
    "other_withdrawal" => {
      explanation: "Wenn du Waren aus deinem Betrieb privat entnimmst, betriebliche Gegenstände privat mitbenutzt oder betriebliche Leistungen für private Zwecke in Anspruch nimmst. Auch ohne Zahlung kann dabei eine steuerliche Einnahme entstehen. Trage den steuerlich anzusetzenden Wert ein.",
      example: "Beispiele: Sachentnahme – du nimmst Ware aus deinem Laden für dich selbst mit. Nutzungsentnahme – du verwendest eine betriebliche Maschine auch für ein privates Projekt. Leistungsentnahme – ein Mitarbeiter deines Betriebs streicht während seiner bezahlten Arbeitszeit deine private Wohnung.",
      assets: true
    },
    "vehicle_use" => {
      explanation: "Wenn du ein Fahrzeug aus deinem Betriebsvermögen auch privat fährst. Hier gehört der steuerlich ermittelte Wert der privaten Nutzung hinein, nicht einfach der Betrag einer Tankrechnung.",
      example: "Beispiel: Du nutzt deinen Firmenwagen am Wochenende privat. Die Bewertung erfolgt je nach Voraussetzungen etwa über ein Fahrtenbuch oder die Ein-Prozent-Regel."
    },
    "expense_goods" => {
      kinds: %w[expense],
      explanation: "Für Waren, die du weiterverkaufst, und Material, das du bei deiner Arbeit verbrauchst. Länger genutzte Betriebsausstattung wie Computer und Maschinen verwaltest du im Anlageverzeichnis.",
      example: "Beispiel: Du kaufst Stoff für deine verkauften Produkte.",
      assets: true
    }
  }.freeze

  ENTRY_COPY = {
    "income" => { amount_label: "Erhaltener Betrag in Euro", amount_hint: "Trage den tatsächlich erhaltenen betrieblichen Betrag ein.", description_label: "Beschreibung", description_hint: "Beschreibe, wofür du das Geld erhalten hast." },
    "expense" => { amount_label: "Gezahlter Betrag in Euro", amount_hint: "Trage den bezahlten Rechnungsbetrag einschließlich Umsatzsteuer ein. Bei gemischter Nutzung gibst du den betrieblichen Anteil weiter unten an.", description_label: "Beschreibung", description_hint: "Beschreibe, wofür du das Geld ausgegeben hast." },
    "deposit" => { amount_label: "Eingelegter Betrag in Euro", amount_hint: "Trage den Geldbetrag ein, den du in den Betrieb eingezahlt hast.", description_label: "Beschreibung", description_hint: "Beschreibe die private Einzahlung, zum Beispiel eine Überweisung auf dein Betriebskonto." },
    "withdrawal" => { amount_label: "Entnommener Betrag in Euro", amount_hint: "Trage den Geldbetrag ein, den du privat entnommen hast.", description_label: "Beschreibung", description_hint: "Beschreibe die private Entnahme, zum Beispiel eine Überweisung vom Betriebskonto auf dein Privatkonto." },
    "noncash_withdrawal" => { amount_label: "Steuerlicher Entnahmewert in Euro", amount_hint: "Trage den steuerlich anzusetzenden Wert der Entnahme ein. Bei privater Nutzung ist das der steuerlich ermittelte Nutzungswert, nicht der Kaufpreis des Gegenstands. Dabei fließt kein Geld.", description_label: "Beschreibung / Bewertungsgrundlage", description_hint: "Beschreibe, was du entnommen oder privat genutzt hast und wie du den steuerlichen Wert ermittelt hast." },
    "noncash_deposit" => { amount_label: "Steuerlicher Einlagewert in Euro", amount_hint: "Trage den steuerlich zulässigen Wert der eingelegten Waren oder des Verbrauchsmaterials ein, nicht automatisch den damaligen Kaufpreis.", description_label: "Beschreibung / Bewertungsgrundlage", description_hint: "Beschreibe, was du in den Betrieb eingelegt hast und wie du den steuerlichen Wert ermittelt hast." }
  }.freeze

  def bookkeeping_entry_copy(kind)
    ENTRY_COPY.fetch(kind, ENTRY_COPY.fetch("income")).merge(
      category_label: { "income" => "Was hast du erhalten?", "expense" => "Ausgabenart",
        "deposit" => "Was hast du eingelegt?", "withdrawal" => "Was hast du entnommen?",
        "noncash_deposit" => "Was hast du eingelegt?", "noncash_withdrawal" => "Was hast du entnommen oder privat genutzt?" }.fetch(kind, "Was hast du erhalten?"),
      account_label: kind == "expense" ? "Bezahlt von" : "Geld erhalten auf",
      private_account_label: kind == "expense" ? "Privatkonto / privat bezahlt" : "Privatkonto"
    )
  end

  def bookkeeping_hint(entry, kinds: [], categories: [], excluded_categories: [], accounts: [], reversal: nil, &block)
    data = { euer_entry_target: "context", kinds: kinds.join(" "), categories: categories.join(" "), excluded_categories: excluded_categories.join(" "), accounts: accounts.join(" "), reversal: reversal }
    visible = (kinds.empty? || kinds.include?(entry.kind)) &&
      (categories.empty? || categories.include?(entry.effective_category)) &&
      !excluded_categories.include?(entry.effective_category) &&
      (accounts.empty? || accounts.include?(entry.payment_account)) &&
      (reversal.nil? || reversal == entry.reversal?)
    tag.small(capture(&block), data: data, hidden: !visible)
  end

  def bookkeeping_date_label(kind)
    case kind
    when "income" then "Datum des Zahlungseingangs"
    when "expense" then "Datum des Zahlungsausgangs"
    when "withdrawal", "noncash_withdrawal" then "Datum der Entnahme"
    when "deposit", "noncash_deposit" then "Datum der Einlage"
    else "Datum"
    end
  end

  def euro(value)
    number_to_currency(value, unit: "€", separator: ",", delimiter: ".", format: "%n %u")
  end

  def euer_reference(key, year)
    line = EuerFields.line(key, year)
    return "Noch keine Feldzuordnung" unless line

    "Zeile #{line}"
  end
end
