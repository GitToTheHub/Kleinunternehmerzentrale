class EuerTaxRules
  # These three automatic values were compared with the instructions accompanying
  # the official forms. This is not a review of every tax rule or special case.
  Rules = Data.define(:meals_percent, :gwg_limit, :interest_threshold)
  YEARS = {
    2025 => Rules.new(meals_percent: 70, gwg_limit: 800, interest_threshold: 2050),
    2026 => Rules.new(meals_percent: 70, gwg_limit: 800, interest_threshold: 2050)
  }.freeze

  # Keep legacy calculations available, but never imply that an unknown year
  # has been checked. Report warnings disclose this compatibility fallback.
  LEGACY = Rules.new(meals_percent: 70, gwg_limit: 800, interest_threshold: 2050)

  def self.for(year) = YEARS.fetch(year, LEGACY)
  def self.checked?(year) = YEARS.key?(year)

  def self.warning(year)
    return if checked?(year)

    "Die automatischen Berechnungswerte für #{year} sind noch nicht jahresbezogen geprüft. Bewirtungsanteil, GWG-Grenze und Schuldzins-Hinweis verwenden vorläufig die bisherigen Werte. Prüfe die EÜR vor der Übertragung."
  end
end
