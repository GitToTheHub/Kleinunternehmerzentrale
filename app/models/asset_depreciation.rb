class AssetDepreciation < ApplicationRecord
  include EuroAmounts
  euro_amounts :amount, :special_amount

  belongs_to :business_asset, inverse_of: :asset_depreciations
  validates :year, numericality: { only_integer: true, greater_than_or_equal_to: 1900, less_than_or_equal_to: 9999 }
  validates :amount, :special_amount, numericality: { greater_than_or_equal_to: 0, less_than: 10_000_000_000 }
  validates :reason, presence: true
  validate :fits_asset

  private

  def fits_asset
    asset = business_asset
    return unless asset && year && amount && special_amount && asset.cost&.positive? && asset.acquired_on

    if year < asset.acquired_on.year || (asset.disposed_on && year > asset.disposed_on.year)
      errors.add(:year, "muss zwischen Zugang und Abgang liegen")
    end
    if asset.depreciation_method == "gwg" || (asset.depreciation_method == "none" && (amount.positive? || special_amount.positive?))
      errors.add(:amount, "ist für diese Abschreibungsmethode nicht zulässig")
    end
    if special_amount.positive? && (asset.depreciation_method != "manual" || !%w[office movable vehicle building].include?(asset.category))
      errors.add(:special_amount, "erfordert eine geeignete Anlagegruppe und manuell bestimmte Jahresbeträge")
    end
    available = year == asset.acquired_on.year ? asset.cost : asset.schedule(year - 1).fetch(:closing)
    errors.add(:amount, "und Sonder-AfA übersteigen den verfügbaren Buchwert") if amount + special_amount > available
    if asset.depreciation_records.any? { |record| record != self && record.year == year }
      errors.add(:year, "ist für dieses Anlagegut bereits erfasst")
    end
  end
end
