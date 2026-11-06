class EuerExpensePolicy < ApplicationRecord
  belongs_to :workspace
  validates :year, inclusion: { in: EuerProfessionAllowance::RULES.keys }, uniqueness: { scope: :workspace_id }
  validates :deduction_method, inclusion: { in: EuerProfessionAllowance::METHODS.keys }
  validates :home_office_method, inclusion: { in: EuerHomeOfficeAllowance::METHODS.keys }
  validates :home_days, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 366 }
  validates :home_months, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 12 }
  validates :home_basis, length: { maximum: 5000 }, allow_nil: true
  validate :usable_allowance
  validate :usable_home_allowance
  validate :valid_daycare_shape

  def daycare_rows=(value)
    super(value.respond_to?(:values) ? value.values : value)
  end

  private

  def valid_daycare_shape
    unless daycare_rows.is_a?(Array) && daycare_rows.size <= 500 && daycare_rows.all? { |row| row.is_a?(Hash) && (row.keys - EuerDaycareAllowance::KEYS).empty? && row.values.all? { |value| value.is_a?(String) || value.is_a?(Numeric) || value.nil? } }
      errors.add(:daycare_rows, "enthält ungültige oder zu viele Betreuungszeiträume")
    end
  end

  def usable_allowance
    return if deduction_method == "actual" || !EuerProfessionAllowance::METHODS.key?(deduction_method) || !workspace || !EuerFields.supported?(year)

    EuerProfessionAllowance.new(validation_report, self).errors.each { |message| errors.add(:base, message) }
  end

  def usable_home_allowance
    return if home_office_method == "none" || !workspace || !EuerFields.supported?(year)

    EuerHomeOfficeAllowance.new(validation_report, self).errors.each { |message| errors.add(:base, message) }
  end

  def validation_report
    BookkeepingReport.new(workspace.bookkeeping_entries, year, assets: workspace.business_assets,
      adjustments: workspace.euer_adjustments, imports: workspace.bookkeeping_imports,
      statement: workspace.euer_statements.find_by(year: year))
  end
end
