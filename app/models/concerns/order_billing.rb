module OrderBilling
  extend ActiveSupport::Concern

  included do
    belongs_to :sales_document, optional: true, autosave: true
    attribute :order_based, :boolean, default: false
    attribute :allocation_basis, :string, default: "total"
    attribute :position_allocations, :json, default: {}
    attr_accessor :order_preparation_error
    euro_amounts :allocation_amount, :allocation_percent
    validates :allocation_basis, inclusion: { in: %w[total positions direct] }
    validate :order_billing_valid
    before_create :use_order_customer
  end

  def position_based? = allocation_basis == "positions" || allocation_mode == "positions"

  def order_total = order_snapshot["total"]&.to_d

  private

  def use_order_customer
    self.customer_id ||= sales_document&.data&.fetch("customer_id", nil)
  end

  def order_billing_valid
    errors.add(:base, order_preparation_error) if order_preparation_error
    return if cancellation? || !sales_document
    unless sales_document.workspace_id == workspace_id && sales_document.order?
      errors.add(:base, "Der Auftrag gehört nicht zu deinem Bereich.")
      return
    end
    return if sales_document.new_record?
    errors.add(:base, "Dieser Auftrag ist bereits vollständig abgerechnet.") if sales_document.closed?
    customer = sales_document.data["customer_id"]
    errors.add(:base, "Bitte verwende denselben Kunden wie im Auftrag.") if customer.present? && customer.to_s != customer_id.to_s
    if billing_kind == "regular" && sales_document.active_invoices.any?
      errors.add(:base, "Bitte erstelle eine Schlussrechnung, damit die bisherigen Anzahlungen und Abschläge berücksichtigt werden.")
    end
    if partial_invoice?
      allocated = sales_document.active_invoices.select(&:partial_invoice?).sum(&:total)
      errors.add(:base, "Die Teilrechnungen würden den vereinbarten Gesamtpreis überschreiten.") if allocated + total > sales_document.total_amount
    end
  end
end
