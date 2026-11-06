# Der eigene Bereich einer Nutzerin oder eines Nutzers. Ohne E-Mail und Passwort ist er ein Gast-Bereich,
# der nur über ein Cookie im Browser erreichbar ist und bei Nichtnutzung gelöscht wird.
class Workspace < ApplicationRecord
  INACTIVITY_LIMIT = 3.months
  WORKFLOW_DEFAULTS = { "units" => ([ "HUR" ] + (InvoiceLine::UNIT_CODES.keys - [ "HUR" ])).freeze }.freeze

  def workflow
    WORKFLOW_DEFAULTS.merge((workflow_settings || {}).slice("units"))
  end

  def invoice_units
    InvoiceLine::UNIT_CODES.slice(*workflow.fetch("units"))
  end

  def default_invoice_unit
    invoice_units.keys.first || "HUR"
  end


  has_secure_password validations: false
  serialize :completed_steps, type: Array, coder: JSON
  has_many :bookkeeping_entries
  has_many :business_assets
  has_many :euer_statements
  has_many :euer_expense_policies
  has_many :euer_adjustments
  has_many :bookkeeping_imports
  has_many :sales_documents
  has_many :invoices
  has_many :invoice_drafts
  has_many :customers
  has_one :business_profile

  normalizes :email, with: ->(email) { email.strip.downcase.presence }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, message: "ist keine gültige E-Mail-Adresse" }, uniqueness: true, allow_nil: true
  validates :password, length: { minimum: 10, message: "ist zu kurz (mindestens 10 Zeichen)" }, allow_nil: true

  # Gilt 30 Minuten und nur einmal: Nach dem Ändern des Passworts ändert sich der Anhang, und der Link wird ungültig.
  generates_token_for :password_reset, expires_in: 30.minutes do
    password_digest&.last(10)
  end

  # Gilt für 7 Tage und nur für die aktuelle Adresse.
  generates_token_for :email_confirmation, expires_in: 7.days do
    email
  end

  # Wer seine E-Mail-Adresse nie bestätigt, wird wie ein Gast behandelt und nach 3 Monaten ohne Aktivität gelöscht.
  scope :expired_guests, -> { where(email: nil).or(where(email_confirmed_at: nil)).where(last_active_at: ...INACTIVITY_LIMIT.ago) }

  before_validation :ensure_token, on: :create
  before_validation(on: :create) { self.last_active_at ||= Time.current }

  def self.purge_expired_guests
    expired_guests.find_each(&:erase!)
  end

  def toggle_step(key)
    return unless StartGuide.keys.include?(key)

    update!(completed_steps: completed_steps.include?(key) ? completed_steps - [ key ] : completed_steps + [ key ])
  end

  def account?
    email.present?
  end

  def email_confirmed?
    email_confirmed_at.present?
  end

  def confirm_email!
    update_column(:email_confirmed_at, Time.current) unless email_confirmed?
  end

  # Zählt als Aktivität, wird aber höchstens einmal pro Tag gespeichert.
  def touch_activity
    update_column(:last_active_at, Time.current) if last_active_at < 1.day.ago
  end

  def register(email:, password:, password_confirmation:)
    self.email = email
    self.password = password
    self.password_confirmation = password_confirmation
    errors.add(:password, "muss angegeben werden") if password.blank?
    errors.empty? && valid? && save
  end

  # Setzt ein neues Passwort und meldet damit alle anderen Geräte ab (neues Cookie-Token).
  def reset_password(password:, password_confirmation:)
    self.password = password
    self.password_confirmation = password_confirmation
    errors.add(:password, "muss angegeben werden") if password.blank?
    return false unless errors.empty? && valid?

    self.token = SecureRandom.base58(32)
    save && (confirm_email!; true)
  end

  # Löscht den ganzen Bereich mit allen Rechnungen und Kundendaten.
  def erase!
    transaction do
      BookkeepingEntry.where(workspace_id: id).delete_all
      InvoiceLine.where(invoice_id: Invoice.where(workspace_id: id).select(:id)).delete_all
      Invoice.where(workspace_id: id).delete_all
      SalesDocument.where(workspace_id: id, kind: "order").delete_all
      SalesDocument.where(workspace_id: id).delete_all
      Customer.where(workspace_id: id).delete_all
      InvoiceDraft.where(workspace_id: id).delete_all
      AssetPrivateUse.where(business_asset_id: BusinessAsset.where(workspace_id: id).select(:id)).delete_all
      AssetDepreciation.where(business_asset_id: BusinessAsset.where(workspace_id: id).select(:id)).delete_all
      BusinessAsset.where(workspace_id: id).delete_all
      EuerStatement.where(workspace_id: id).delete_all
      EuerExpensePolicy.where(workspace_id: id).delete_all
      EuerAdjustment.where(workspace_id: id).delete_all
      BookkeepingImport.where(workspace_id: id).delete_all
      BusinessProfile.where(workspace_id: id).delete_all
      delete
    end
  end

  private

  def ensure_token
    self.token ||= SecureRandom.base58(32)
  end
end
