# Current billed amounts per order, independent of whether payment has arrived.
class InvoiceBillingOverview
  def self.call(invoices)
    partials = invoices.select { |invoice| invoice.partial_invoice? && !invoice.cancelled_invoice_id && !invoice.cancellation }
    groups = partials.group_by { |invoice| invoice.sales_document_id ? [ :order, invoice.sales_document_id ] : [ :invoice, invoice.billing_root_id_for_order ] }
    groups.each_with_object({}) do |(_key, group), result|
      total = group.filter_map(&:order_total).first
      summary = { total: total, billed: group.sum(&:total), count: group.size }
      group.each { |invoice| result[invoice.id] = summary }
    end
  end
end
