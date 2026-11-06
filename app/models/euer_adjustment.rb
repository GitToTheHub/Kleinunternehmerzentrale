class EuerAdjustment < ApplicationRecord
  include EuroAmounts
  euro_amounts :amount, signed: true

  belongs_to :workspace
  validates :year, inclusion: { in: EuerFields::SOURCES.keys }
  validates :field_key, inclusion: { in: EuerFields::DEFINITIONS.keys }
  validate { errors.add(:field_key, "ist für dieses Steuerjahr nicht vorgesehen") if EuerFields::DEFINITIONS.key?(field_key) && !EuerFields.line(field_key, year) }
  validates :description, presence: true
  validates :amount, numericality: { other_than: 0, greater_than: -10_000_000_000, less_than: 10_000_000_000 }
end
