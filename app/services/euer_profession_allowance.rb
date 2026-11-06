# Whole-business election only. Mixed activities and nonstandard years need an
# allocation, so they must not silently use this simplified automatic method.
class EuerProfessionAllowance
  METHODS = {
    "actual" => "Tatsächliche Betriebsausgaben",
    "writer_main" => "Hauptberuflich schriftstellerisch oder journalistisch",
    "eligible_side" => "Begünstigte wissenschaftliche, künstlerische, schriftstellerische oder Lehr-/Prüfungs-Nebentätigkeit",
    "daycare" => "Selbständige Kindertagespflege"
  }.freeze
  RULES = {
    2025 => { "writer_main" => [ 30, 3600 ], "eligible_side" => [ 25, 900 ] }.freeze,
    2026 => { "writer_main" => [ 30, 3600 ], "eligible_side" => [ 25, 900 ] }.freeze
  }.freeze

  attr_reader :report, :policy, :amounts

  def initialize(report, policy, amounts = report.actual_field_totals)
    @report, @policy, @amounts = report, policy, amounts
  end

  def elected? = policy.present? && policy.deduction_method != "actual"

  def errors
    return [] unless elected?

    messages = []
    messages << "Die gewählte Ausgabenmethode gehört zu einem anderen Steuerjahr." if policy.year != report.year
    rule_known = policy.deduction_method == "daycare" ? EuerDaycareAllowance::RULES.key?(report.year) : RULES.dig(report.year, policy.deduction_method)
    messages << "Für dieses Jahr oder diese Pauschale ist keine geprüfte Berechnungsregel hinterlegt." unless rule_known
    messages << "Bestätige, dass die gesamte Tätigkeit dieses Betriebs unter die gewählte Pauschale fällt und keine steuerbefreite Übungsleitertätigkeit einbezogen ist." unless policy.eligibility_confirmed?
    details = report.details
    unless details["income_type"] == "3" && EuerPreparationCheck::SOLE_PROPRIETOR_FORMS.any? { |form| form.casecmp?(details["legal_form"].to_s.strip) }
      messages << "Für die automatische Betriebsausgabenpauschale müssen die Betriebsangaben ein Einzelunternehmen mit Einkünften aus selbständiger Arbeit ausweisen."
    end
    messages << "Für abweichende Wirtschaftsjahre ist eine gesonderte Berechnung erforderlich." if EuerPreparationCheck.new(report).noncalendar_period?
    messages << "Es gibt Umsatzsteueraufteilungen aus einer anderen Besteuerung. Prüfe diese Angaben vor einer automatischen Betriebsausgabenpauschale gesondert." if report.legacy_tax_data?
    # No guesses about revenue allocation or special gain corrections.
    unsupported = EuerFields::DEFINITIONS.values.select do |field|
      next false if policy.deduction_method == "daycare" && field.key == "tax_exempt_other"

      (field.effect == :income && field.key != "income_small") || %i[profit_plus profit_minus].include?(field.effect) || field.section == "27" || %w[expense_vineyard expense_forestry expense_livestock_reserve input_vat].include?(field.key)
    end
    if unsupported.any? { |field| !amounts.fetch(field.key).zero? }
      messages << "Es gibt weitere Einnahmen oder Gewinnkorrekturen. Die automatische Pauschale kann diese nicht sicher der begünstigten Tätigkeit zuordnen. Verwende tatsächliche Ausgaben oder eine gesondert ermittelte Aufteilung."
    end
    if !amounts.fetch("expense_profession_allowance").zero?
      messages << "Eine Betriebsausgabenpauschale wurde bereits als EÜR-Summe oder Ergänzung erfasst. Entferne diese Doppelung oder verwende die bisherige manuelle Berechnung."
    end
    if report.entries.any? { |entry| entry.kind == "expense" && entry.reversal? }
      messages << "Es gibt Ausgabenerstattungen. Prüfe deren Behandlung im Zusammenhang mit der Betriebsausgabenpauschale gesondert."
    end
    messages << "Die maßgeblichen Betriebseinnahmen dürfen nicht negativ sein." if revenue.negative?
    if policy.deduction_method == "daycare"
      messages << "Bestätige die besonderen Voraussetzungen der Kindertagespflege-Pauschale." unless policy.daycare_eligibility_confirmed?
      messages.concat(EuerDaycareAllowance.new(policy.daycare_rows, report.year).errors)
      messages << "Steuerfreie Einnahmen dürfen nicht negativ sein." if amounts.fetch("tax_exempt_other").negative?
    end
    messages
  end

  def applicable? = elected? && errors.empty?
  def revenue
    amounts.fetch("income_small") - (policy&.deduction_method == "daycare" ? amounts.fetch("tax_exempt_other") : 0.to_d)
  end

  def amount
    return 0.to_d unless applicable?

    return [ EuerDaycareAllowance.new(policy.daycare_rows, report.year).amount, revenue ].min if policy.deduction_method == "daycare"

    percent, limit = RULES.fetch(report.year).fetch(policy.deduction_method)
    [ (revenue * percent / 100).round(2), limit.to_d ].min
  end

  def apply
    return amounts unless applicable?

    amounts.dup.tap do |result|
      EuerFields::DEFINITIONS.each_value do |field|
        result[field.key] = 0.to_d if %i[expense expense_reduction].include?(field.effect) || BookkeepingEntry::DISALLOWED.value?(field.key)
      end
      result["property_repairs_details"] = 0.to_d
      result["expense_profession_allowance"] = amount
    end
  end
end
