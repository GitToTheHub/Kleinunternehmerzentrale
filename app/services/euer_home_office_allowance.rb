class EuerHomeOfficeAllowance
  METHODS = { "none" => "Keine automatische Pauschale", "days" => "Tagespauschale für Arbeit zuhause", "annual" => "Jahrespauschale für ein häusliches Arbeitszimmer" }.freeze
  RULES = {
    2025 => { day: 6, annual: 1260, month: 105 }.freeze,
    2026 => { day: 6, annual: 1260, month: 105 }.freeze
  }.freeze

  attr_reader :report, :policy, :amounts

  def initialize(report, policy, amounts = report.actual_field_totals)
    @report, @policy, @amounts = report, policy, amounts
  end

  def elected? = policy.present? && policy.home_office_method != "none"
  def field_key = policy&.home_office_method == "annual" ? "expense_home_office" : "expense_home_days"

  def errors
    return [] unless elected?

    messages = []
    messages << "Für diese Pauschale oder dieses Steuerjahr fehlt eine geprüfte Regel." unless RULES.key?(report.year) && METHODS.key?(policy.home_office_method) && policy.year == report.year
    messages << "Bestätige die Voraussetzungen und den Ausschluss doppelter Ansätze für die Pauschale zuhause." unless policy.home_eligibility_confirmed?
    messages << "Dokumentiere die zugrunde gelegten Tage oder Monate." if policy.home_basis.blank?
    messages << "Eine Betriebsausgabenpauschale deckt die Betriebsausgaben bereits ab. Die Pauschale zuhause darf hier nicht zusätzlich angesetzt werden." if policy.deduction_method != "actual"
    unless %w[2 3].include?(report.details["income_type"]) && EuerPreparationCheck::SOLE_PROPRIETOR_FORMS.any? { |form| form.casecmp?(report.details["legal_form"].to_s.strip) }
      messages << "Für die automatische Zuordnung müssen die Betriebsangaben ein Einzelunternehmen mit Gewerbebetrieb oder selbständiger Arbeit ausweisen. Bei anderen Konstellationen ist eine gesonderte Aufteilung nötig."
    end
    messages << "Für abweichende Wirtschaftsjahre ist eine gesonderte Berechnung erforderlich." if EuerPreparationCheck.new(report).noncalendar_period?
    if %w[expense_home_days expense_home_office home_office_disallowed expense_second_home].any? { |key| !amounts.fetch(key).zero? }
      messages << "Es gibt bereits Angaben zum Arbeitszimmer, zur Tagespauschale oder doppelten Haushaltsführung. Prüfe Überschneidungen und verwende bei Bedarf eine gesonderte Aufteilung statt dieser automatischen Pauschale."
    end
    count = policy.home_office_method == "annual" ? policy.home_months : policy.home_days
    limit = policy.home_office_method == "annual" ? 12 : (Date.gregorian_leap?(report.year) ? 366 : 365)
    messages << "Die Anzahl der Tage oder Monate liegt außerhalb des erlaubten Bereichs." unless count.is_a?(Integer) && count.between?(0, limit)
    messages
  end

  def applicable? = elected? && errors.empty?

  def amount
    return 0.to_d unless applicable?

    rules = RULES.fetch(report.year)
    value = policy.home_office_method == "annual" ? policy.home_months * rules.fetch(:month) : policy.home_days * rules.fetch(:day)
    [ value, rules.fetch(:annual) ].min.to_d
  end

  def apply(values)
    return values unless applicable?

    values.merge(field_key => values.fetch(field_key) + amount)
  end
end
