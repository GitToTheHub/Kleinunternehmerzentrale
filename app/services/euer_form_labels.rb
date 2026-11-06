# Original captions from the BMF forms linked in EuerFields::SOURCES.
# Keep these separate from the shorter labels used in everyday bookkeeping.
class EuerFormLabels
  LABELS = {
    "income_small_details" => "davon nicht steuerbare Umsätze sowie Umsätze nach § 19 Abs. 2 Satz 1 Nr. 1 und 2 sowie Satz 2 UStG",
    "income_agriculture" => "Betriebseinnahmen als Land- und Forstwirt, soweit die Durchschnittssatzbesteuerung nach § 24 UStG angewandt wird",
    "expense_profession_allowance" => "Betriebsausgabenpauschale für bestimmte Berufsgruppen",
    "expense_vineyard" => "Sachlicher Bebauungskostenrichtbetrag und Ausbaukostenrichtbeträge für Weinbaubetriebe (Übertrag aus Zeile 13 der Anlage LuF)",
    "expense_forestry" => "Betriebsausgabenpauschale für Forstwirte (Übertrag aus Zeile 17 der Anlage LuF)",
    "expense_livestock_reserve" => "Bildung Rücklage Tierbewertung bei Land- und Forstwirten (Übertrag aus Zeile 18 der Anlage LuF)",
    "property_repairs_details" => "in den sonstigen Aufwendungen für betrieblich genutzte Grundstücke enthaltene Erhaltungsaufwendungen",
    "partial_income_total" => "Bereits berücksichtigte Beträge, für die das Teileinkünfteverfahren bzw. § 8b KStG gilt – Gesamtbetrag",
    "reserve_create" => "Rücklagen nach § 6c i. V. m. § 6b EStG, R 6.6 EStR – Bildung/Übertragung",
    "reserve_transfer" => "Übertragung von stillen Reserven nach § 6c i. V. m. § 6b EStG, R 6.6 EStR",
    "allocation_create" => "Ausgleichsposten nach § 4g EStG – Bildung/Übertragung",
    "reserve_release" => "Rücklagen nach § 6c i. V. m. § 6b EStG, R 6.6 EStR – Auflösung",
    "allocation_release" => "Ausgleichsposten nach § 4g EStG – Auflösung",
    "income_small" => "Betriebseinnahmen als umsatzsteuerlicher Kleinunternehmer (nach § 19 Abs. 1 UStG) ohne Beträge laut Zeilen 18 bis 22",
    "income_taxable" => "Umsatzsteuerpflichtige Betriebseinnahmen (ohne solche zum ermäßigten Steuersatz von 0 %)",
    "income_exempt" => "Betriebseinnahmen, die umsatzsteuerfrei (§ 4 UStG) oder nicht umsatzsteuerbar sind oder nach § 12 Abs. 3 UStG dem ermäßigten Steuersatz von 0 % unterliegen oder für die der Leistungsempfänger die Umsatzsteuer nach § 13b UStG schuldet",
    "vat_collected" => "Vereinnahmte Umsatzsteuer sowie Umsatzsteuer auf unentgeltliche Wertabgaben",
    "vat_refund" => "Vom Finanzamt erstattete und ggf. verrechnete Umsatzsteuer (Die Regelung zum 10-Tageszeitraum - § 11 Abs. 1 Satz 2 EStG - ist zu beachten.)",
    "asset_income" => "Veräußerung oder Entnahme von Anlagevermögen",
    "vehicle_use" => "Private Kfz-Nutzung",
    "other_withdrawal" => "Sonstige Sach-, Nutzungs- und Leistungsentnahmen",
    "afa_property" => "AfA auf Grundstücke/grundstücksgleiche Rechte (Übertrag aus Zeile 22 der Anlage AVEÜR)",
    "afa_intangible" => "AfA auf immaterielle Wirtschaftsgüter (Übertrag aus Zeile 37 der Anlage AVEÜR)",
    "afa_movable" => "AfA auf bewegliche Wirtschaftsgüter (Übertrag aus Zeile 63 der Anlage AVEÜR)",
    "afa_special" => "Sonderabschreibungen nach § 7b EStG und § 7g Abs. 5 und 6 EStG (Übertrag der Summe der Zeilen 12 und 62 der Anlage AVEÜR)",
    "asset_reduction" => "Herabsetzungsbeträge nach § 7g Abs. 2 Satz 3 EStG (Erläuterungen auf gesondertem Blatt)",
    "expense_gwg" => "Aufwendungen für geringwertige Wirtschaftsgüter nach § 6 Abs. 2 EStG",
    "pool_release" => "Auflösung Sammelposten nach § 6 Abs. 2a EStG (Übertrag aus Zeile 82 der Anlage AVEÜR)",
    "asset_residual" => "Restbuchwerte der ausgeschiedenen Anlagegüter (Übertrag der Summe der Beträge aus Zeilen 7, 14, 20, 26, 32, 38, 45, 53, 60, 86, 91 der Anlage AVEÜR)",
    "input_vat" => "Gezahlte und nach § 15 UStG abziehbare Vorsteuerbeträge",
    "vat_payment" => "An das Finanzamt gezahlte und ggf. verrechnete Umsatzsteuer (Die Regelung zum 10-Tageszeitraum - § 11 Abs. 2 Satz 2 EStG - ist zu beachten.)",
    "expense_other" => "Übrige unbeschränkt abziehbare Betriebsausgaben (auch zurückgezahlte Hilfen/Zuschüsse aufgrund der Corona-Pandemie)",
    "expense_gifts" => "Geschenke – abziehbar",
    "gifts_disallowed" => "Geschenke – nicht abziehbar",
    "expense_meals" => "Bewirtungsaufwendungen – abziehbar",
    "meals_disallowed" => "Bewirtungsaufwendungen – nicht abziehbar",
    "expense_meal_allowance" => "Verpflegungsmehraufwendungen",
    "expense_home_office" => "Aufwendungen für ein häusliches Arbeitszimmer (siehe Anleitung) – abziehbar",
    "home_office_disallowed" => "Aufwendungen für ein häusliches Arbeitszimmer (siehe Anleitung) – nicht abziehbar",
    "expense_home_days" => "Tagespauschale für die Tätigkeit in der häuslichen Wohnung (siehe Anleitung)",
    "expense_limited" => "Sonstige beschränkt abziehbare Betriebsausgaben – abziehbar",
    "limited_disallowed" => "Sonstige beschränkt abziehbare Betriebsausgaben – nicht abziehbar",
    "expense_vehicle_leasing" => "Leasingkosten",
    "expense_vehicle_tax" => "Steuern, Versicherungen und Maut",
    "expense_vehicle" => "Sonstige tatsächliche Fahrtkosten ohne AfA und Zinsen (z. B. Reparaturen, Wartungen, Treibstoff, Kosten für Flugstrecken, Kosten für öffentliche Verkehrsmittel)",
    "expense_private_vehicle" => "Fahrtkosten für nicht zum Betriebsvermögen gehörende Fahrzeuge (Nutzungseinlage)",
    "commute_reduction" => "Fahrtkosten für Wege zwischen Wohnung und erster Betriebsstätte; Familienheimfahrten (pauschaliert oder tatsächlich)",
    "expense_commute" => "Mindestens abziehbare Fahrtkosten für Wege zwischen Wohnung und erster Betriebsstätte (Entfernungspauschale); Familienheimfahrten",
    "expense_disallowed" => "Nicht abziehbare Beträge (Beispiele siehe Anleitung)",
    "tax_exempt_allowance" => "abzüglich steuerfreier Einnahmen nach § 3 Nr. 26, 26a, 26b EStG",
    "tax_exempt_other" => "abzüglich steuerfreier Einnahmen nach § 3 EStG (ohne Nr. 26, 26a, 26b und Teileinkünfteverfahren)",
    "tax_exempt_restructuring" => "abzüglich steuerfreier Einnahmen nach § 3a EStG",
    "tax_add_allowance" => "zuzüglich nicht abziehbarer Betriebsausgaben im Zusammenhang mit steuerfreien Einnahmen nach § 3 Nr. 26, 26a, 26b EStG",
    "tax_add_exempt" => "zuzüglich nicht abziehbarer Betriebsausgaben nach § 3c Abs. 1 EStG",
    "tax_add_restructuring" => "zuzüglich nicht abziehbarer Betriebsausgaben nach § 3c Abs. 4 EStG",
    "reserve_profit" => "zuzüglich Gewinnzuschlag nach § 6c i. V. m. § 6b Abs. 7 und 10 EStG",
    "iab_deduction" => "abzüglich Investitionsabzugsbeträge nach § 7g Abs. 1 EStG",
    "method_change" => "Hinzurechnungen und Abrechnungen bei Wechsel der Gewinnermittlungsart (Erläuterungen auf gesondertem Blatt)",
    "partnership_result" => "Ergebnisanteile aus Beteiligungen an Personengesellschaften (auch Kostenträgergemeinschaften)",
    "partial_income_correction" => "Bereits berücksichtigte Beträge, für die das Teileinkünfteverfahren bzw. § 8b KStG gilt – Korrekturbetrag",
    "interest_addback" => "Hinzurechnungsbetrag nach § 4 Abs. 4a EStG",
    "withdrawals" => "Entnahmen einschließlich Sach-, Leistungs- und Nutzungsentnahmen",
    "deposits" => "Einlagen einschließlich Sach-, Leistungs- und Nutzungseinlagen"
  }.freeze

  def self.label(key, year)
    raise ArgumentError, "Unbekanntes EÜR-Jahr" unless EuerFields.supported?(year)

    if %w[iab_add_1 iab_add_2 iab_add_3].include?(key)
      return "zuzüglich Hinzurechnung der Investitionsabzugsbeträge nach § 7g Abs. 2 Satz 1 EStG aus #{year - key.last.to_i} (Erläuterungen auf gesondertem Blatt)"
    end
    if %w[investment_correction investment_total].include?(key)
      return "Bereits berücksichtigte Beträge, für die Steuerbefreiungen nach InvStG gelten (ohne Beträge lt. Zeile #{EuerFields.line('partial_income_correction', year)}; Erläuterungen auf gesondertem Blatt) – #{key == "investment_total" ? "Gesamtbetrag" : "Korrekturbetrag"}"
    end

    if key == "property_repairs_details"
      return "in Zeile #{EuerFields.line('expense_property', year)} enthaltene Erhaltungsaufwendungen"
    end

    LABELS.fetch(key) { EuerFields::DEFINITIONS.fetch(key).label }
  end

  def self.reference(key, year)
    line = EuerFields.line(key, year)
    return "Keine Zeilenzuordnung für dieses Jahr" unless line

    "Zeile #{line}"
  end
end
