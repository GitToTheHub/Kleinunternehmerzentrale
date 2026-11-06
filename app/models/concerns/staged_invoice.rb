# Aufträge bündeln Teilrechnungen; ältere Abläufe behalten den ersten Vorschuss als Bezug.
# Die Schlussrechnung bewahrt die angerechneten Zahlungen als unveränderlichen Stand.
module StagedInvoice
  extend ActiveSupport::Concern

  BILLING_KINDS = { "regular" => "Rechnung", "advance" => "Anzahlungsrechnung", "progress" => "Abschlagsrechnung", "final" => "Schlussrechnung" }.freeze

  included do
    attribute :settlement_invoice_ids, :json, default: []
    belongs_to :billing_root, class_name: "Invoice", optional: true
    validates :billing_kind, inclusion: { in: BILLING_KINDS.keys }
    validate :staged_billing_valid
    validate :settlement_selection_valid
    before_validation :prepare_deducted_payments, on: :create
  end

  def partial_invoice? = %w[advance progress].include?(billing_kind)
  def final_invoice? = billing_kind == "final"
  def staged_invoice? = billing_kind != "regular"
  def billing_label = BILLING_KINDS.fetch(billing_kind, "Rechnung")
  def billing_root_id_for_order = billing_root_id || (id if partial_invoice?)

  def selected_settlement_ids
    raw = persisted? ? order_snapshot.fetch("settlement_invoice_ids", []) : settlement_invoice_ids
    return [] unless raw.is_a?(Array)
    raw.select { |id| id.to_s.match?(/\A[1-9][0-9]*\z/) }.map(&:to_i).uniq
  end

  def selected_settlement_invoices
    return Invoice.none unless workspace
    workspace.invoices.where(id: selected_settlement_ids, billing_kind: %w[advance progress], sales_document_id: nil, cancelled_invoice_id: nil)
  end

  def base_order_invoices
    return sales_document.invoices if sales_document&.persisted?
    return Invoice.none unless workspace && billing_root_id_for_order
    workspace.invoices.where(id: billing_root_id_for_order).or(workspace.invoices.where(billing_root_id: billing_root_id_for_order))
  end

  def order_invoices
    base = base_order_invoices
    return base unless final_invoice? && workspace && selected_settlement_ids.any?
    roots = selected_settlement_invoices.map(&:billing_root_id_for_order)
    additional = workspace.invoices.where(id: roots).or(workspace.invoices.where(billing_root_id: roots))
    workspace.invoices.where(id: base.select(:id)).or(additional)
  end

  def active_final_invoice
    return unless workspace
    related = order_invoices
    finals = related.where(billing_kind: "final", cancelled_invoice_id: nil)
    partial_ids = related.where(billing_kind: %w[advance progress], cancelled_invoice_id: nil).pluck(:id)
    if partial_ids.any?
      referencing = workspace.invoices.where(billing_kind: "final", cancelled_invoice_id: nil)
        .where("EXISTS (SELECT 1 FROM json_each(invoices.deducted_payments) AS payment WHERE CAST(json_extract(payment.value, '$.invoice_id') AS INTEGER) IN (?))", partial_ids)
      finals = finals.or(referencing)
    end
    finals.includes(:cancellation).detect { |item| !item.cancellation }
  end

  def settled_in_final? = partial_invoice? && active_final_invoice.present?
  def deducted_total = deducted_payments.sum { |payment| payment.fetch("amount").to_d }
  def payment_total = total - deducted_total
  def payment_total_in_euros = foreign_currency? ? (payment_total * exchange_rate).round(2) : payment_total

  private

  def prepare_deducted_payments
    return if cancellation?

    self.deducted_payments = []
    return unless final_invoice? && workspace
    self.order_snapshot = order_snapshot.merge("settlement_invoice_ids" => selected_settlement_ids) if selected_settlement_ids.any?
    return unless billing_root_id || sales_document_id || selected_settlement_ids.any?

    self.deducted_payments = order_invoices.where(billing_kind: %w[advance progress], cancelled_invoice_id: nil)
      .includes(:cancellation, :payment_entry).order(:issued_on, :id).filter_map do |item|
      next if item.cancellation || !item.payment_entry

      { "invoice_id" => item.id, "number" => item.invoice_number, "issued_on" => item.issued_on.iso8601,
        "paid_on" => item.payment_entry.paid_on.iso8601, "amount" => item.payment_entry.amount.to_s("F") }
    end
  end

  def settlement_selection_valid
    return if cancellation? || persisted?
    raw = settlement_invoice_ids
    unless raw.is_a?(Array) && raw.all? { |id| id.to_s.match?(/\A[1-9][0-9]*\z/) }
      errors.add(:base, "Bitte wähle gültige Anzahlungs- oder Abschlagsrechnungen aus.")
      return
    end
    return if selected_settlement_ids.empty?
    unless final_invoice?
      errors.add(:base, "Bisherige Anzahlungen und Abschläge können nur in einer Schlussrechnung angerechnet werden.")
      return
    end
    selected = selected_settlement_invoices.to_a
    if selected.length != selected_settlement_ids.length
      errors.add(:base, "Die ausgewählten Teilrechnungen sind nicht verfügbar oder gehören nicht zu deinem Bereich.")
    end
    partials = order_invoices.where(billing_kind: %w[advance progress], cancelled_invoice_id: nil).includes(:cancellation).reject(&:cancellation)
    if customer_id.blank? || selected.any? { |invoice| invoice.customer_id != customer_id } || partials.any? { |invoice| invoice.customer_id != customer_id }
      errors.add(:base, "Wähle nur Teilrechnungen für denselben gespeicherten Kunden wie in der Schlussrechnung.")
    end
    if partials.any? { |invoice| invoice.foreign_currency? || invoice.standard_taxed? || invoice.sales_document_id.present? && invoice.sales_document_id != sales_document_id }
      errors.add(:base, "Diese Teilrechnungen können nicht gemeinsam angerechnet werden.")
    end
  end

  def staged_billing_valid
    return if cancellation?

    if !staged_invoice?
      errors.add(:base, "Eine normale Rechnung kann keinem Teilrechnungsauftrag zugeordnet werden.") if billing_root_id.present?
      return
    end
    errors.add(:base, "Teil- und Schlussrechnungen werden derzeit nur in Euro ohne Umsatzsteuerausweis unterstützt.") if foreign_currency? || standard_taxed?
    errors.add(:base, "Der Rechnungsbetrag darf nicht negativ sein.") if total.negative?
    errors.add(:base, "Wähle einen Auftrag oder bisherige Anzahlungen und Abschläge für die Schlussrechnung aus.") if final_invoice? && billing_root_id.blank? && sales_document.nil? && selected_settlement_ids.empty?
    return if billing_root_id.blank? && sales_document.nil? && selected_settlement_ids.empty?

    if !sales_document && billing_root_id.present?
      root = workspace&.invoices&.find_by(id: billing_root_id)
      unless root&.partial_invoice? && root.billing_root_id.nil?
        errors.add(:billing_root, "ist kein Teilrechnungsauftrag aus deinem Bereich")
        return
      end
      errors.add(:base, "Bitte verwende für diesen Auftrag denselben Kunden.") unless customer_id.present? && customer_id == root.customer_id
    end
    existing_final = active_final_invoice
    errors.add(:base, "Für diesen Auftrag gibt es bereits eine Schlussrechnung. Storniere diese zuerst.") if existing_final && existing_final.id != id
    return unless final_invoice?

    partials = order_invoices.where(billing_kind: %w[advance progress], cancelled_invoice_id: nil).includes(:cancellation, payment_entry: :refunds).reject(&:cancellation)
    if partials.empty? || partials.any? { |item| !item.payment_entry || item.payment_entry.refunds.any? || item.payment_entry.paid_on > issued_on }
      errors.add(:base, "Erfasse zuerst alle Zahlungen zu diesem Auftrag. Unbezahlte Teilrechnungen müssen bezahlt oder storniert sein; zurückgezahlte Teilrechnungen müssen vor der Schlussrechnung storniert und gegebenenfalls neu erstellt werden.")
    end
    errors.add(:base, "Der Gesamtbetrag des Auftrags darf nicht kleiner als die angerechneten Zahlungen sein.") if payment_total.negative?
  end
end
