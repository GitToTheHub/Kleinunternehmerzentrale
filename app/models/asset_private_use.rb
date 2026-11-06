class AssetPrivateUse < ApplicationRecord
  include EuroAmounts
  euro_amounts :business_percent, :manual_amount
  MODES = { "depreciation" => "Privaten Anteil der Abschreibung berechnen", "manual" => "Fachlich ermittelten Jahreswert verwenden" }.freeze

  belongs_to :business_asset, inverse_of: :asset_private_uses
  validates :year, numericality: { only_integer: true, greater_than_or_equal_to: 1900, less_than_or_equal_to: 9999 }
  validates :business_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :basis, presence: true
  validates :calculation_mode, inclusion: { in: MODES.keys }
  validates :manual_amount, numericality: { greater_than_or_equal_to: 0, less_than: 10_000_000_000 }, if: -> { calculation_mode == "manual" }
  validate :fits_asset

  def field_key = business_asset.category == "vehicle" ? "vehicle_use" : "other_withdrawal"

  def amount
    return manual_amount.to_d if calculation_mode == "manual"
    return 0.to_d unless year && business_percent && business_asset.acquired_on && business_asset.cost&.positive?

    (business_asset.schedule(year).fetch(:ordinary) * (100 - business_percent) / 100).round(2)
  end

  private

  def fits_asset
    asset = business_asset
    return unless asset && year

    if asset.acquired_on && (year < asset.acquired_on.year || (asset.disposed_on && year > asset.disposed_on.year))
      errors.add(:year, "muss zwischen Zugang und Abgang liegen")
    end
    if asset.private_use_records.any? { |record| record != self && record.year == year }
      errors.add(:year, "ist für dieses Anlagegut bereits erfasst")
    end
    if calculation_mode == "depreciation" && (!%w[office movable intangible].include?(asset.category) || asset.depreciation_method == "none" || asset.input_vat.to_d.positive? || (asset.cost&.positive? && asset.acquired_on && asset.schedule(year)[:special].positive?))
      errors.add(:calculation_mode, "kann diesen Sonderfall nicht aus dem Nutzungsanteil berechnen. Verwende einen fachlich ermittelten Jahreswert.")
    end
    if business_percent == 100 && calculation_mode == "manual" && manual_amount.to_d.positive?
      errors.add(:manual_amount, "muss bei ausschließlich betrieblicher Nutzung null sein")
    end
    if calculation_mode == "depreciation" && manual_amount.present?
      errors.add(:manual_amount, "darf bei berechnetem Privatanteil nicht zusätzlich angegeben werden")
    end
  end
end
