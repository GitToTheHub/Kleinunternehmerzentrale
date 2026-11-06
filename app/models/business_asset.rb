class BusinessAsset < ApplicationRecord
  include EuroAmounts
  euro_amounts :business_use_percent, :cost, :gwg_net_value, :input_vat, :withdrawal_value, :withdrawal_vat

  CATEGORIES = { "office" => "Büroausstattung", "movable" => "Sonstige bewegliche Anlagegüter", "vehicle" => "Fahrzeug",
                 "intangible" => "Immaterielles Anlagegut", "building" => "Gebäude / Grundstücksrecht", "land" => "Grund und Boden" }.freeze
  METHODS = { "linear" => "Linear über die Nutzungsdauer", "gwg" => "Sofortabzug als geringwertiges Wirtschaftsgut",
              "manual" => "Jährliche Abschreibung selbst vorgeben", "none" => "Nicht abschreibbar" }.freeze
  ORIGINS = { "purchase" => "Betrieblich angeschafft", "contribution" => "Aus Privatvermögen eingelegt" }.freeze
  DISPOSALS = { "sale" => "Verkauft", "withdrawal" => "Privat entnommen", "scrap" => "Verschrottet / zerstört" }.freeze

  belongs_to :workspace
  has_many :asset_depreciations, dependent: :destroy, inverse_of: :business_asset
  has_many :asset_private_uses, dependent: :destroy, inverse_of: :business_asset
  accepts_nested_attributes_for :asset_private_uses, allow_destroy: true,
    reject_if: ->(attributes) { %w[year business_percent basis manual_amount].all? { |key| attributes[key].blank? } }
  accepts_nested_attributes_for :asset_depreciations, allow_destroy: true,
    reject_if: ->(attributes) { attributes["year"].blank? && attributes["amount"].blank? && attributes["reason"].blank? && [ "", "0", "0.0", "0,00" ].include?(attributes["special_amount"].to_s) }

  validates :business_use_percent, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validates :usage_basis, presence: true, if: -> { business_use_percent && business_use_percent < 100 }
  validates :name, :acquired_on, presence: true
  validates :category, inclusion: { in: CATEGORIES.keys }
  validates :origin, inclusion: { in: ORIGINS.keys }
  validates :depreciation_method, inclusion: { in: METHODS.keys }
  validates :cost, numericality: { greater_than: 0, less_than: 10_000_000_000 }
  validates :input_vat, :withdrawal_vat, numericality: { greater_than_or_equal_to: 0, less_than: 10_000_000_000 }
  validates :withdrawal_value, numericality: { greater_than_or_equal_to: 0, less_than: 10_000_000_000 }, allow_nil: true
  validates :useful_life, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100 }, if: -> { depreciation_method == "linear" }
  validates :payment_account, inclusion: { in: %w[business private] }
  validate :valid_private_use_records
  validate :asset_rules
  validate :schedule_within_cost
  validate :no_imported_depreciation_overlap

  def depreciation_field
    { "intangible" => "afa_intangible", "building" => "afa_property" }.fetch(category, "afa_movable")
  end

  def tax_disposal_date
    depreciation_method == "none" && disposal_kind == "sale" ? disposal_recognized_on : disposed_on
  end

  def schedule(year)
    return empty_schedule unless acquired_on && cost && year >= acquired_on.year

    book = cost
    opening = 0.to_d
    ordinary = 0.to_d
    special = 0.to_d
    overrides = depreciation_records.index_by(&:year)
    # Linear deductions end after the final partial year. Manual records may be
    # sparse; do not iterate thousands of empty calendar years.
    years = overrides.keys.select { |value| value && value <= year && value >= acquired_on.year }
    if depreciation_method == "linear" && useful_life.to_i.positive?
      years |= (acquired_on.year..[ year, acquired_on.year + useful_life ].min).to_a
    elsif depreciation_method == "gwg"
      years |= [ acquired_on.year ]
    end
    years |= [ year ]
    years.sort.each do |current_year|
      break if tax_disposal_date && current_year > tax_disposal_date.year

      opening = current_year == acquired_on.year ? 0.to_d : book if current_year == year
      override = overrides[current_year]
      deduction = if override
        override.amount.to_d
      elsif depreciation_method == "gwg" && current_year == acquired_on.year
        cost
      elsif depreciation_method == "linear"
        linear_amount(current_year)
      else
        0.to_d
      end
      extra = override&.special_amount.to_d
      if current_year == year
        ordinary = [ deduction, book ].min
        special = [ extra, book - ordinary ].min
      end
      book -= [ deduction + extra, book ].min
    end
    return empty_schedule if tax_disposal_date && year > tax_disposal_date.year

    residual = tax_disposal_date&.year == year ? book : 0.to_d
    { opening: opening, additions: acquired_on.year == year ? cost : 0.to_d,
      ordinary: ordinary, special: special, residual: residual, closing: tax_disposal_date&.year == year ? 0.to_d : book }
  end

  def private_use_records = asset_private_uses.reject(&:marked_for_destruction?)
  def private_use_for(year) = private_use_records.find { |record| record.year == year }

  def depreciation_records = asset_depreciations.reject(&:marked_for_destruction?)

  private

  def valid_private_use_records
    private_use_records.each do |record|
      errors.add(:base, "Private Nutzung: #{record.errors.full_messages.to_sentence}") unless record.valid?
    end
  end

  def no_imported_depreciation_overlap
    return unless workspace && acquired_on

    if workspace.bookkeeping_imports.any? { |import| import.asset_overlap?(self) }
      errors.add(:base, "Für diesen Zeitraum wurden bereits Abschreibungen, Restbuchwerte oder zugehörige Einlagen und Entnahmen als EÜR-Summen übernommen. Entferne diese Übernahme und übernimm sie ohne die betreffenden Anlagenbeträge, bevor du die Anlagegüter mit ihrer vollständigen Abschreibungshistorie erfasst.")
    end
  end

  def empty_schedule
    %i[opening additions ordinary special residual closing].index_with { 0.to_d }
  end

  def linear_amount(year)
    return 0.to_d unless useful_life.to_i.positive?

    before, after, total_months = linear_months(year)
    ((cost * after / total_months).round(2) - (cost * before / total_months).round(2))
  end

  def linear_months(year)
    total_months = useful_life * 12
    before = [ [ (year - acquired_on.year) * 12 - acquired_on.month + 1, 0 ].max, total_months ].min
    last_month = disposed_on&.year == year ? disposed_on.month : 12
    after = [ [ (year - acquired_on.year) * 12 + last_month - acquired_on.month + 1, 0 ].max, total_months ].min
    [ before, after, total_months ]
  end

  def asset_rules
    if acquired_on && disposed_on && disposed_on < acquired_on
      errors.add(:disposed_on, "darf nicht vor dem Zugang liegen")
    end
    if disposed_on
      errors.add(:disposal_kind, "muss ausgewählt werden") unless DISPOSALS.key?(disposal_kind)
      if disposal_kind == "withdrawal" && (!withdrawal_value || withdrawal_value.negative?)
        errors.add(:withdrawal_value, "muss als steuerlicher Entnahmewert angegeben werden")
      end
      if depreciation_method == "none" && disposal_kind == "sale"
        if disposal_recognized_on.blank? || disposal_recognized_on < disposed_on
          errors.add(:disposal_recognized_on, "muss den Zufluss des Verkaufserlöses angeben und darf nicht vor dem Abgang liegen")
        end
      end
    elsif disposal_kind.present? || withdrawal_value.present? || withdrawal_vat.to_d.positive?
      errors.add(:disposed_on, "muss für einen Abgang angegeben werden")
    end
    if disposal_kind != "withdrawal" && (withdrawal_value.present? || withdrawal_vat.to_d.positive?)
      errors.add(:withdrawal_value, "ist nur bei einer Privatentnahme zulässig")
    end
    if category == "land" && depreciation_method != "none"
      errors.add(:depreciation_method, "Grund und Boden ist nicht abschreibbar")
    end
    if depreciation_method == "gwg"
      gwg_limit = EuerTaxRules.for(acquired_on&.year).gwg_limit
      errors.add(:category, "GWG müssen selbständig nutzbare, bewegliche Anlagegüter sein") unless %w[office movable].include?(category)
      unless gwg_net_value && gwg_net_value.positive? && gwg_net_value <= gwg_limit && cost && gwg_net_value <= cost
        errors.add(:gwg_net_value, "muss den Wert ohne enthaltene Umsatzsteuer angeben und darf #{gwg_limit} Euro nicht übersteigen")
      end
      errors.add(:asset_depreciations, "sind beim GWG-Sofortabzug nicht zusätzlich zulässig") if depreciation_records.any?
    end
    if origin == "purchase"
      errors.add(:paid_on, "muss für den Kauf angegeben werden") if paid_on.blank?
    elsif input_vat.to_d.positive? || paid_on.present?
      errors.add(:paid_on, "bei einer Sacheinlage keine Kaufzahlung oder Vorsteuer erfassen")
    end
  end

  def schedule_within_cost
    return unless cost&.positive? && acquired_on
    return if depreciation_records.any? { |record| record.year.nil? || record.amount.nil? || record.special_amount.nil? }

    years = depreciation_records.map(&:year)
    if years.uniq.size != years.size
      errors.add(:asset_depreciations, "dürfen jedes Jahr nur einmal enthalten")
    end
    depreciation_records.each do |record|
      if record.year < acquired_on.year || (disposed_on && record.year > disposed_on.year)
        errors.add(:asset_depreciations, "müssen zwischen Zugang und Abgang liegen")
      end
      if depreciation_method == "none" && (record.amount.positive? || record.special_amount.positive?)
        errors.add(:asset_depreciations, "sind bei nicht abschreibbaren Gütern nicht zulässig")
      end
      if record.special_amount.positive? && !%w[office movable vehicle building].include?(category)
        errors.add(:asset_depreciations, "Sonderabschreibung ist für diese Anlagegruppe nicht vorgesehen")
      end
      if record.special_amount.positive? && depreciation_method != "manual"
        errors.add(:depreciation_method, "bei Sonderabschreibungen die Jahresbeträge manuell vorgeben; Begünstigungszeitraum und anschließende Restwert-AfA müssen berücksichtigt werden")
      end
      available = acquired_on.year == record.year ? cost : schedule(record.year - 1).fetch(:closing)
      if record.amount + record.special_amount > available
        errors.add(:asset_depreciations, "übersteigen im Jahr #{record.year} den verfügbaren Buchwert")
      end
    end
  end
end
