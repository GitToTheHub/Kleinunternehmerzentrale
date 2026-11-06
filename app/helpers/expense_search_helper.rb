module ExpenseSearchHelper
  # Suchbegriffe helfen bei der Auswahl; sie ersetzen keine Prüfung des Sachverhalts.
  EXPENSE_SEARCH_TERMS = {
    "expense_it" => "vps hosting servermiete cloud domain software softwareabo lizenz bildlizenz saas ionos strato adobe github",
    "expense_phone" => "telefon telefonrechnung mobilfunk mobilfunkvertrag internetanschluss internetvertrag dsl congstar telekom vodafone ionos",
    "expense_supplies" => "büromaterial bürobedarf papier stifte druckerpapier toner druckerpatrone porto briefmarke fachliteratur",
    "expense_goods" => "handelsware wareneinkauf verkaufsware rohstoffe material weiterverkauf wiederverkauf verarbeiten",
    "expense_services" => "freelancer subunternehmer fremdleistung dienstleister auftragnehmer honorar",
    "expense_training" => "kurs seminar workshop schulung fortbildung weiterbildung fachbuch fachbücher",
    "expense_advice" => "steuerberater steuerberatung rechtsanwalt anwalt buchführung buchhaltungskosten",
    "expense_rent" => "büromiete raummiete ladenmiete werkstattmiete studiomiete coworking geschäftsraum",
    "expense_repairs" => "reparatur wartung instandhaltung computerreparatur maschinenwartung",
    "expense_leasing" => "gerätemiete werkzeugmiete maschinenmiete computerleasing",
    "expense_insurance" => "betriebshaftpflicht berufshaftpflicht betriebsversicherung applecare kammerbeitrag ihk handwerkskammer",
    "expense_advertising" => "werbung anzeige anzeigen googleads flyer visitenkarten werbedruck",
    "expense_transport" => "versand versandkosten verpackung versandkarton versandkartons paketversand spedition",
    "expense_waste" => "entsorgung müll abfall schrott",
    "expense_staff" => "gehalt löhne lohn mitarbeiter personal",
    "expense_travel" => "hotel übernachtung reisenebenkosten",
    "expense_vehicle" => "fahrtkosten bahnticket zugticket taxi benzin diesel tanken",
    "expense_vehicle_leasing" => "autoleasing fahrzeugleasing kfzleasing",
    "expense_vehicle_tax" => "kfzsteuer kfzversicherung maut fahrzeugversicherung",
    "expense_asset_interest" => "investitionsdarlehen investitionskredit",
    "expense_interest" => "kreditzinsen schuldzinsen darlehenszinsen",
    "expense_meals" => "geschäftsessen kundenessen bewirtung restaurant",
    "expense_gifts" => "kundengeschenk geschenke präsent",
    "expense_home_office" => "arbeitszimmer",
    "expense_other" => "bankgebühr bankgebühren kontoführung kontoführungsgebühren zahlungsgebühren"
  }.freeze

  def expense_search_categories
    BookkeepingEntry::SMALL_BUSINESS_CATEGORIES.fetch("expense").map do |key|
      { key: key, label: EuerFields.selection_label(key),
        terms: [ EuerFields.selection_label(key), BookkeepingEntriesHelper::EVERYDAY_CATEGORIES[key], EXPENSE_SEARCH_TERMS[key] ].compact.join(" "),
        example: BookkeepingEntriesHelper::EXPENSE_EXAMPLES[key] }
    end
  end
end
