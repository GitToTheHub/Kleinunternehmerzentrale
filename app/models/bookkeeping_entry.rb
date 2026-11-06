class BookkeepingEntry < ApplicationRecord
  include EuroAmounts
  euro_amounts :amount, :vat_amount, :deductible_percent, :business_percent, :cash_private_amount

  KINDS = { "income" => "Einnahme", "expense" => "Ausgabe", "deposit" => "Private Geldeinlage", "withdrawal" => "Private Geldentnahme",
            "noncash_withdrawal" => "Sach-, Nutzungs- oder Leistungsentnahme", "noncash_deposit" => "Sacheinlage (Ware / Verbrauchsmaterial)" }.freeze
  INCOME_CATEGORIES = %w[income_small income_taxable income_exempt vat_collected vat_refund asset_income].freeze
  EXPENSE_CATEGORIES = %w[expense_goods expense_services expense_staff expense_rent expense_second_home expense_property expense_phone
    expense_travel expense_training expense_advice expense_leasing expense_repairs expense_insurance expense_it expense_supplies expense_waste
    expense_transport expense_advertising expense_asset_interest expense_interest input_vat vat_payment expense_other expense_gifts expense_meals
    expense_home_office expense_limited expense_vehicle_leasing expense_vehicle_tax expense_vehicle].freeze
  CATEGORIES = {
    "income" => INCOME_CATEGORIES, "expense" => EXPENSE_CATEGORIES,
    "noncash_withdrawal" => %w[other_withdrawal vehicle_use], "noncash_deposit" => %w[expense_goods],
    "deposit" => [], "withdrawal" => []
  }.freeze
  SMALL_BUSINESS_CATEGORIES = CATEGORIES.transform_values do |keys|
    keys.select { |key| EuerFields.small_business?(key) }.freeze
  end.freeze
  DISALLOWED = { "expense_gifts" => "gifts_disallowed", "expense_meals" => "meals_disallowed",
                 "expense_home_office" => "home_office_disallowed", "expense_limited" => "limited_disallowed" }.freeze
  DEFAULT_CATEGORIES = { "income" => "income_small", "expense" => "expense_other", "noncash_withdrawal" => "other_withdrawal", "noncash_deposit" => "expense_goods" }.freeze

  belongs_to :invoice, optional: true, inverse_of: :payment_entry
  belongs_to :workspace
  belongs_to :original_entry, class_name: "BookkeepingEntry", optional: true
  has_many :refunds, class_name: "BookkeepingEntry", foreign_key: :original_entry_id, dependent: :restrict_with_error
  before_validation :normalize_category
  before_validation :refund_tax_share
  before_validation :normalize_cash_allocation
  validates :paid_on, :description, presence: true
  validates :kind, inclusion: { in: KINDS.keys }
  validates :amount, numericality: { greater_than: 0, less_than: 10_000_000_000 }
  validates :vat_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :deductible_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :payment_account, inclusion: { in: %w[business private cash] }
  validate :cash_allocation_rules
  validates :business_percent, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validates :usage_notes, presence: { message: "muss den betrieblichen Anteil begründen" }, if: -> { business_percent && business_percent < 100 }
  validate :business_share_only_for_expenses
  validates :tax_year, numericality: { only_integer: true, greater_than_or_equal_to: 1900, less_than_or_equal_to: 9999 }, allow_nil: true
  validate :category_matches_kind
  validate :tax_amounts
  validate :invoice_payment_rules
  validate :settled_payment_unchanged
  before_destroy :protect_settled_payment
  validate :refund_rules
  validate :outside_imported_period
  validates :invoice_id, uniqueness: true, allow_nil: true

  scope :in_year, ->(year) {
    where(tax_year: year).or(where(tax_year: nil, paid_on: Date.new(year, 1, 1)..Date.new(year, 12, 31)))
  }

  def effective_year = tax_year || paid_on.year
  def effective_category = category.presence || DEFAULT_CATEGORIES[kind]
  def signed_amount = reversal? ? -amount : amount
  def signed_vat = reversal? ? -vat_amount : vat_amount
  def tax_base = signed_amount - signed_vat

  def deductible_share
    deductible_percent || (effective_category == "expense_meals" ? EuerTaxRules.for(original_entry&.effective_year || tax_year || paid_on&.year).meals_percent.to_d : 100.to_d)
  end

  def business_amount = kind == "expense" ? (signed_amount * business_percent / 100).round(2) : signed_amount
  def business_tax_base = kind == "expense" ? (tax_base * business_percent / 100).round(2) : tax_base
  def business_vat = kind == "expense" ? (signed_vat * business_percent / 100).round(2) : signed_vat
  def private_amount = signed_amount - business_amount
  def income_private_withdrawal
    return 0.to_d unless kind == "income"
    return signed_amount if payment_account == "private"
    return reversal? ? -cash_private_amount.to_d : cash_private_amount.to_d if payment_account == "cash"

    0.to_d
  end
  def deductible_amount = (business_tax_base * deductible_share / 100).round(2)

  def refundable_amount
    amount - refunds.where.not(id: nil).sum(:amount)
  end

  def refundable? = !reversal? && %w[income expense].include?(kind) && refundable_amount.positive?

  def refund_attributes
    { kind: kind, category: effective_category, deductible_percent: deductible_percent, business_percent: business_percent, usage_notes: usage_notes,
      reversal: true, reference: reference, vat_amount: 0, invoice_id: nil }
  end

  private

  def normalize_cash_allocation
    if payment_account != "cash"
      self.cash_usage = nil
      self.cash_private_amount = nil
    elsif cash_usage == "business"
      self.cash_private_amount = 0
    elsif cash_usage == "private"
      self.cash_private_amount = amount
    end
  end

  def cash_allocation_rules
    return unless payment_account == "cash"

    errors.add(:payment_account, "Bargeld ist hier nur für Einnahmen und deren Rückzahlungen verfügbar") unless kind == "income"
    unless %w[business private split].include?(cash_usage)
      errors.add(:cash_usage, "muss ausgewählt werden")
    end
    if cash_usage == "split" && (!cash_private_amount || !amount || cash_private_amount <= 0 || cash_private_amount >= amount)
      errors.add(:cash_private_amount, "muss größer als null und kleiner als der erhaltene Eurobetrag sein")
    end
  end

  def business_share_only_for_expenses
    if kind != "expense" && business_percent && business_percent != 100
      errors.add(:business_percent, "ist nur bei laufenden Betriebsausgaben zulässig")
    end
  end

  def outside_imported_period
    return unless workspace && paid_on

    overlap = workspace.bookkeeping_imports.find_by(year: paid_on.year)
    overlap ||= workspace.bookkeeping_imports.find_by(year: tax_year) if tax_year
    if overlap && (paid_on <= overlap.covered_through || (tax_year == overlap.year && overlap.covered_through == Date.new(overlap.year, 12, 31)))
      errors.add(:paid_on, "liegt in einem bereits übernommenen EÜR-Zeitraum. Entferne zuerst die Summenübernahme, wenn du diesen Zeitraum einzeln erfassen möchtest.")
    end
  end

  def refund_tax_share
    return unless original_entry && amount && original_entry.amount&.positive?

    self.vat_amount = (original_entry.vat_amount * amount / original_entry.amount).round(2)
  end

  def refund_rules
    if original_entry_id.present?
      original = original_entry
      unless original && original.workspace_id == workspace_id && !original.reversal? && %w[income expense].include?(original.kind)
        errors.add(:base, "Der ursprüngliche Vorgang ist für diese Rückzahlung nicht verfügbar.")
        return
      end
      unless reversal? && kind == original.kind && effective_category == original.effective_category && deductible_percent == original.deductible_percent && business_percent == original.business_percent && invoice_id.nil?
        errors.add(:base, "Die Rückzahlung muss die Vorgangsart und Kategorie des ursprünglichen Vorgangs übernehmen.")
      end
      used = original.refunds.where.not(id: id).sum(:amount)
      errors.add(:amount, "übersteigt den noch erstattbaren Betrag") if amount && amount + used > original.amount
      errors.add(:paid_on, "darf nicht vor dem ursprünglichen Zahlungsdatum liegen") if paid_on && paid_on < original.paid_on
      errors.add(:paid_on, "darf für eine erfolgte Rückzahlung nicht in der Zukunft liegen") if paid_on && paid_on > Date.current
    elsif persisted? && refunds.exists?
      errors.add(:base, "Bei einem Vorgang mit Rückzahlungen können Art, Kategorie und steuerlicher Anteil nicht geändert werden.") if kind_changed? || category_changed? || deductible_percent_changed? || business_percent_changed? || reversal_changed?
      errors.add(:amount, "darf die bereits erfassten Rückzahlungen nicht unterschreiten") if amount && amount < refunds.sum(:amount)
    end
  end

  def settled_payment_unchanged
    return unless new_record? || has_changes_to_save?

    linked = [ invoice, original_entry&.invoice ]
    linked << workspace&.invoices&.find_by(id: invoice_id_in_database) if persisted?
    if linked.compact.any?(&:settled_in_final?)
      errors.add(:base, "Diese Zahlung ist in einer Schlussrechnung angerechnet. Storniere zuerst die Schlussrechnung.")
    end
  end

  def protect_settled_payment
    if invoice&.settled_in_final?
      errors.add(:base, "Diese Zahlung ist in einer Schlussrechnung angerechnet. Storniere zuerst die Schlussrechnung.")
      throw :abort
    end
  end

  def invoice_payment_rules
    return if invoice_id.blank?

    if !invoice || invoice.workspace_id != workspace_id
      errors.add(:invoice, "ist in deinem Bereich nicht verfügbar")
      return
    end
    if (new_record? || invoice_id_changed?) && !invoice.payment_recordable?
      errors.add(:invoice, "kann nicht als bezahlt erfasst werden")
    end
    unless kind == "income" && !reversal? && %w[income_small asset_income].include?(effective_category) && vat_amount.to_d.zero?
      errors.add(:invoice, "kann nur mit einem Zahlungseingang ohne Steueraufteilung verknüpft werden")
    end
    if paid_on && paid_on > Date.current
      errors.add(:paid_on, "darf für einen erhaltenen Zahlungseingang nicht in der Zukunft liegen")
    end
    if invoice.currency == "EUR" && amount && amount != invoice.payment_total
      errors.add(:amount, "muss für eine vollständig bezahlte Rechnung dem Rechnungsbetrag entsprechen; Teilzahlungen können noch nicht zugeordnet werden")
    end
  end

  def normalize_category
    self.category = nil if %w[deposit withdrawal].include?(kind)
    self.category = "expense_goods" if kind == "noncash_deposit" && category.blank?
  end

  def category_matches_kind
    if effective_category.present? && !CATEGORIES.fetch(kind, []).include?(effective_category)
      errors.add(:category, "passt nicht zur Art des Vorgangs")
    end
  end

  def tax_amounts
    return unless amount && vat_amount

    errors.add(:vat_amount, "darf den Gesamtbetrag nicht übersteigen") if vat_amount > amount
    if vat_amount.positive? && (%w[deposit withdrawal noncash_deposit].include?(kind) || %w[income_small vat_collected vat_refund input_vat vat_payment].include?(effective_category))
      errors.add(:vat_amount, "ist für diese Kategorie nicht zulässig; erfasse hier den Betrag ohne zusätzliche Steueraufteilung")
    end
    if deductible_percent.present? && kind != "expense"
      errors.add(:deductible_percent, "ist nur für Betriebsausgaben zulässig")
    end
    if kind == "noncash_deposit" && reversal?
      errors.add(:reversal, "ist bei Sacheinlagen nicht zulässig")
    end
    if tax_year.present? && (!%w[income expense].include?(kind) || (paid_on && (tax_year - paid_on.year).abs > 1))
      errors.add(:tax_year, "darf nur Zahlungen dem laufenden oder angrenzenden Steuerjahr zuordnen")
    end
  end
end
