class BookkeepingImport < ApplicationRecord
  include EuerDetails
  ASSET_FIELDS = %w[afa_property afa_intangible afa_movable afa_special asset_reduction expense_gwg pool_release asset_residual].freeze

  belongs_to :workspace
  validates :year, inclusion: { in: EuerFields::SOURCES.keys }, uniqueness: { scope: :workspace_id }
  validates :covered_through, :source, presence: true
  validates :notes, length: { maximum: 4000 }
  validates :source, length: { maximum: 200 }
  validate :period_valid
  validate :amounts_valid
  validate :no_overlapping_records

  def field_amounts = amounts.transform_values { |amount| BigDecimal(amount.to_s) }
  def asset_amounts? = (amounts.keys & ASSET_FIELDS).any? { |key| amounts[key].to_d.nonzero? }
  def asset_overlap?(asset)
    return false unless asset.acquired_on && covered_through
    usage = asset.private_use_for(year)
    if usage && usage.amount.positive? && [ usage.field_key, "withdrawals" ].any? { |key| amounts[key].to_d.nonzero? }
      return true
    end
    return false if assets_managed_separately? && !asset_amounts?
    return true if asset_amounts? && asset.acquired_on <= covered_through

    deposit_date = asset.origin == "contribution" ? asset.acquired_on : (asset.payment_account == "private" ? asset.paid_on : nil)
    if amounts["deposits"].to_d.nonzero? && deposit_date && deposit_date.year == year && deposit_date <= covered_through
      return true
    end
    asset.disposal_kind == "withdrawal" && asset.disposed_on && asset.disposed_on.year == year && asset.disposed_on <= covered_through &&
      %w[asset_income withdrawals].any? { |key| amounts[key].to_d.nonzero? }
  end
  def total_for(effect) = EuerFields::DEFINITIONS.values.select { |field| field.effect == effect }.sum { |field| field_amounts.fetch(field.key, 0.to_d) }
  def income = total_for(:income)
  def expenses = total_for(:expense) - total_for(:expense_reduction)
  def surplus = income - expenses + total_for(:profit_plus) - total_for(:profit_minus)

  private

  def period_valid
    return unless covered_through && EuerFields.supported?(year)

    errors.add(:covered_through, "muss im gewählten Steuerjahr liegen") unless covered_through.year == year
    errors.add(:covered_through, "darf nicht in der Zukunft liegen") if covered_through > Date.current
  end

  def amounts_valid
    unless amounts.is_a?(Hash) && amounts.any? && amounts.size <= EuerFields::DEFINITIONS.size
      errors.add(:base, "Trage mindestens eine EÜR-Position mit einem Betrag ein.")
      return
    end
    amounts.each do |key, value|
      errors.add(:base, "Unbekannte oder für dieses Steuerjahr ungeeignete EÜR-Position: #{key}") unless EuerFields::DEFINITIONS.key?(key) && EuerFields.line(key, year)
      unless value.to_s.match?(/\A-?\d+(?:\.\d{1,2})?\z/) && value.to_d.abs < 10_000_000_000
        errors.add(:base, "Ungültiger Betrag für #{key}.")
      end
    end
    { "income_small_details" => "income_small", "property_repairs_details" => "expense_property" }.each do |part, total|
      if amounts.key?(part) && (amounts[part].to_d.negative? || amounts[part].to_d > amounts[total].to_d)
        errors.add(:base, "Die Davon-Angabe #{EuerFields::DEFINITIONS.fetch(part).label} darf den zugehörigen Gesamtbetrag nicht überschreiten.")
      end
    end
    if assets_managed_separately? && asset_amounts?
      errors.add(:base, "Wenn du Anlagegüter separat verwaltest, müssen deren Abschreibungen und Restbuchwerte aus den übernommenen Summen herausgenommen werden.")
    end
  end

  def no_overlapping_records
    return unless workspace && covered_through && EuerFields.supported?(year) && amounts.is_a?(Hash)

    entries = workspace.bookkeeping_entries.where(paid_on: Date.new(year, 1, 1)..covered_through)
    entries = entries.or(workspace.bookkeeping_entries.where(tax_year: year)) if covered_through == Date.new(year, 12, 31)
    if entries.exists?
      errors.add(:base, "Im Übernahmezeitraum sind bereits Vorgänge erfasst. Entferne zuerst die Überschneidungen oder übernimm stattdessen die einzelnen Zahlungen; die Summen würden sonst doppelt zählen.")
    end
    if workspace.euer_adjustments.where(year: year, field_key: amounts.keys).exists?
      errors.add(:base, "Für übernommene Positionen gibt es bereits steuerliche Ergänzungen. Prüfe und entferne doppelte Beträge vor der Übernahme.")
    end
    if workspace.business_assets.any? { |asset| asset_overlap?(asset) }
      errors.add(:base, "Vorhandene Anlagegüter berücksichtigen Abschreibungen, Restbuchwerte und gegebenenfalls Einlagen oder Entnahmen bereits selbst. Übernimm deren Beträge nicht zusätzlich als EÜR-Summen.")
    end
  end
end
