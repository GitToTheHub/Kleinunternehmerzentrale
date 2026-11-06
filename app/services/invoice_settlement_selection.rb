# Paid direct advances are selectable as complete groups of related invoices.
# Fixed-scope orders keep their existing automatic final-invoice workflow.
class InvoiceSettlementSelection
  def self.groups(workspace)
    return [] unless workspace&.persisted?
    finals = workspace.invoices.where(billing_kind: "final", cancelled_invoice_id: nil).includes(:cancellation).reject(&:cancellation)
    used_ids = finals.flat_map { |invoice| invoice.deducted_payments.map { |entry| entry["invoice_id"].to_i } }.to_set
    closed_roots = finals.filter_map(&:billing_root_id).to_set
    partials = workspace.invoices.where(billing_kind: %w[advance progress], sales_document_id: nil, cancelled_invoice_id: nil)
      .includes(:cancellation, :invoice_lines, payment_entry: :refunds).reject(&:cancellation)
    grouped = partials.group_by(&:billing_root_id_for_order)
    roots = workspace.invoices.where(id: grouped.keys).index_by(&:id)
    grouped.filter_map do |root_id, invoices|
      root = roots[root_id]
      next unless root&.customer_id.present? && root.sales_document_id.nil? && !closed_roots.include?(root_id)
      next if invoices.any? { |invoice| used_ids.include?(invoice.id) || invoice.customer_id != root.customer_id || invoice.foreign_currency? || invoice.standard_taxed? || !invoice.payment_entry || invoice.payment_entry.refunds.any? }
      { root: root, invoices: invoices.sort_by { |invoice| [ invoice.issued_on, invoice.id ] }, amount: invoices.sum { |invoice| invoice.payment_entry.amount } }
    end
  end
end
