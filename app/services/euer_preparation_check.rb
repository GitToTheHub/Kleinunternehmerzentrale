# Preparation guidance, not a tax assessment or a gate for recording payments.
# Basis: official EÜR instructions, general information and supplementary forms.
class EuerPreparationCheck
  CALENDAR_WARNING = "Ein abweichendes Wirtschaftsjahr ist angegeben. Die laufende Berechnung verwendet Kalenderjahre. Prüfe die fachliche zeitliche Abgrenzung aller übernommenen und ergänzten Beträge.".freeze
  BASE_DETAILS = %w[taxpayer_name tax_number activity legal_form income_type owner property_disposal].freeze
  SOLE_PROPRIETOR_FORMS = [
    "Einzelunternehmen", "Einzelgewerbe", "Einzelgewerbetreibende(r)",
    "Einzelgewerbetreibender", "Einzelgewerbetreibende", "Freiberufler", "Freiberuflerin",
    "Angehörige(r) der freien Berufe", "Angehöriger der freien Berufe", "Angehörige der freien Berufe"
  ].freeze

  attr_reader :report

  def initialize(report)
    @report = report
  end

  def details = report.details

  def missing_keys
    keys = BASE_DETAILS.select { |key| details[key].blank? }
    keys << "first_name" if details["legal_form"].present? && sole_proprietor? && details["first_name"].blank?
    keys += %w[period_start period_end].select { |key| details[key].blank? } if details["income_type"] == "1"
    keys
  end

  def notices
    messages = []
    if details["income_type"] == "1"
      messages << "Land- und Forstwirtschaft: Prüfe das Wirtschaftsjahr und gegebenenfalls die Anlage LuF, etwa für Weinbau- oder Forstpauschalen. Die App berechnet diese Sonderwerte nicht selbst. Fachlich ermittelte Beträge kannst du in den passenden EÜR-Positionen ergänzen. Die Auswahl aktiviert keine Umsatzsteuerberechnung nach § 24 UStG."
    end
    if details["legal_form"].present? && !sole_proprietor?
      messages << "Rechtsform prüfen: Die automatische Gewinnübersicht ist auf Einzelunternehmen ausgerichtet. Für die angegebene Rechtsform ist keine vollständige Unterstützung bestätigt. Prüfe, ob die EÜR anwendbar ist und zusätzliche Berechnungen oder Anlagen benötigt werden; Sonder- und Ergänzungsrechnungen erstellt die App nicht automatisch."
    end
    if details["termination"].present?
      messages << "Betriebsbeendigung oder Übertragung: Prüfe erforderliche Übergangs-, Aufgabe- oder Veräußerungsberechnungen. Die Auswahl allein berechnet diese Werte nicht; die laufenden Zahlungssummen können hierfür unvollständig sein."
    end
    if details["owner"] == "3"
      messages << "Mehrere Betriebsinhaber: Prüfe, ob eine gemeinsame Gewinnermittlung und zusätzliche Angaben für Beteiligte erforderlich sind. Die App verteilt den Gewinn nicht automatisch auf mehrere Personen."
    end
    if details["property_disposal"] == "1"
      messages << "Grundstücksabgang: Prüfe Erlös beziehungsweise Entnahmewert, Restbuchwert und weitere steuerliche Auswirkungen. Diese Auswahl legt keinen Anlagenabgang an. Erfasse den tatsächlichen Abgang im Anlageverzeichnis und ergänze fachlich ermittelte Sonderwerte."
    end
    messages << CALENDAR_WARNING if noncalendar_period?
    if details["tax_number"].to_s.strip.match?(/\A[A-Za-z]{2}/)
      messages << "Steuernummer prüfen: Hier ist eine Umsatzsteuer- oder Wirtschafts-Identifikationsnummer eingetragen. Diese ersetzt die Betriebssteuernummer nicht."
    end
    messages
  end

  def relevant_fields
    return [] unless details["income_type"] == "1"

    %w[income_agriculture expense_vineyard expense_forestry expense_livestock_reserve].select do |key|
      EuerFields.line(key, report.year)
    end
  end

  def warnings = (notices + report.warnings).uniq

  def noncalendar_period?
    return false if details["period_start"].blank? && details["period_end"].blank?

    details["period_start"] != "#{report.year}-01-01" || details["period_end"] != "#{report.year}-12-31"
  end

  private

  def sole_proprietor?
    SOLE_PROPRIETOR_FORMS.any? { |form| form.casecmp?(details["legal_form"].strip) }
  end
end
