# Converts an agreed scope into a payable advance without changing its agreed prices.
# Called afresh for form, preview and finalization; finalization runs under workspace lock.
class OrderInvoicePreparation
  def initialize(workspace, attributes)
    @workspace = workspace
    @attributes = attributes.to_h.stringify_keys
  end

  def call
    invoice = @workspace.invoices.new(@attributes)
    document = if invoice.sales_document_id
      @workspace.sales_documents.find(invoice.sales_document_id)
    end
    if invoice.partial_invoice? && invoice.allocation_basis == "direct"
      if document
        invoice.order_preparation_error = "Für einen gespeicherten Gesamtauftrag verwende die gemeinsame Berechnung oder Positionsanteile."
      else
        invoice.order_based = false
        invoice.allocation_mode = "direct"
        invoice.order_preparation_error = "Der angeforderte Betrag muss größer als 0 sein." unless invoice.total.positive?
      end
      return invoice
    end
    return invoice unless document || (invoice.partial_invoice? && invoice.order_based?)
    if document && !document.order?
      invoice.order_preparation_error = "Bitte übernimm das Angebot zuerst als Auftrag."
      return invoice
    end
    source = document ? document.invoice_attributes : SalesDocument.input_data(@attributes)
    scope = @workspace.invoices.new(source.except("invoice_lines_attributes").merge("billing_kind" => "regular", "customer_update_mode" => "invoice_only"))
    source_lines = source.fetch("invoice_lines_attributes", {}).reject { |_key, line| ActiveModel::Type::Boolean.new.cast(line["_destroy"]) }
    source_lines.each_value { |line| scope.invoice_lines.build(line.except("id", "_destroy")) }
    unless scope.invoice_lines.all?(&:valid?)
      invoice.order_preparation_error = "Bitte prüfe die Positionen des Gesamtauftrags."
      return invoice
    end
    total = scope.total
    lines = scope.invoice_lines.map { |line| JSON.parse(line.attributes.slice(*InvoiceLine::COPIED_ATTRIBUTES).to_json) }
    invoice.order_snapshot = { "total" => total.to_s("F"), "lines" => lines }
    if invoice.partial_invoice?
      if invoice.position_based?
        prepare_positions(invoice, scope, source_lines.keys, document)
      else
        prepare_total(invoice, scope, document)
      end
      return invoice if invoice.order_preparation_error
      if document
        previous = document.active_invoices.select(&:partial_invoice?)
        invoice.order_snapshot["previous_invoices"] = previous.map do |item|
          { "number" => item.invoice_number, "amount" => item.total.to_s("F"),
            "paid_amount" => (item.payment_entry&.amount || 0.to_d).to_s("F") }
        end
      end
    else
      invoice.invoice_lines.clear
      lines.each { |line| invoice.invoice_lines.build(line) }
    end
    invoice.sales_document = document || @workspace.sales_documents.new(kind: "order", document_date: invoice.issued_on || Date.current, data: SalesDocument.input_data(@attributes))
    invoice
  end

  private

  def prepare_total(invoice, scope, document)
    total = scope.total
    amount = requested_amount(invoice, total)
    return if invoice.order_preparation_error
    invoice.allocation_amount = amount
    totals = scope.invoice_lines.map(&:line_total)
    used = OrderPositionAllocation.used(document, totals)
    remaining = totals.zip(used).map { |price, billed| [ price - billed, 0.to_d ].max }
    if amount > remaining.sum
      invoice.order_preparation_error = "Der angeforderte Betrag überschreitet den noch nicht abgerechneten Auftragsbetrag."
      return
    end
    invoice.order_snapshot["allocations"] = OrderPositionAllocation.distribute(amount, remaining).each_with_index.map do |share, index|
      { "source_index" => index, "mode" => "allocated", "value" => share.to_s("F"), "amount" => share.to_s("F") }
    end
    invoice.order_snapshot["show_scope_positions"] = true
    invoice.invoice_lines.clear
    percentage = invoice.allocation_mode == "percent" ? "#{invoice.allocation_percent.to_s('F').sub(/\.0+\z/, '')} % " : ""
    details = "<p>Vereinbarter Gesamtpreis: #{money(total)}. #{percentage}#{invoice.billing_label}: #{money(amount)}.</p>"
    scope.invoice_lines.each do |line|
      details += "<p><strong>#{ERB::Util.h(line.description)}</strong> – #{money(line.line_total)}</p>#{line.details_html}"
    end
    invoice.invoice_lines.build(description: "#{percentage}#{invoice.billing_label} auf den Gesamtauftrag", details: details, quantity: 1, unit_code: "LS", unit_price: amount, tax_rate: 0)
  end

  def prepare_positions(invoice, scope, keys, document)
    allocations = []
    amounts = []
    totals = scope.invoice_lines.map(&:line_total)
    used = OrderPositionAllocation.used(document, totals)
    values = invoice.position_allocations
    unless values.is_a?(Hash) && (values.keys - keys.map(&:to_s)).empty?
      invoice.order_preparation_error = "Bitte prüfe die Anteile der Auftragspositionen."
      return
    end
    scope.invoice_lines.each_with_index do |line, index|
      raw = values[keys[index].to_s]
      input = OrderPositionAllocation::Input.new(raw.is_a?(Hash) ? raw.slice("mode", "value") : {})
      unless input.valid? && (input.mode != "percent" || input.value <= 100)
        invoice.order_preparation_error = "Bitte gib für Position #{index + 1} einen gültigen Anteil von 0 bis 100 Prozent oder einen Betrag ein."
        return
      end
      amount = input.mode == "percent" ? (line.line_total * input.value / 100).round(2) : input.value
      if amount > line.line_total || amount + used[index] > line.line_total
        invoice.order_preparation_error = "Der Anteil für Position #{index + 1} überschreitet den noch nicht abgerechneten Positionsbetrag."
        return
      end
      amounts << amount
      allocations << { "source_index" => index, "mode" => input.mode, "value" => input.value.to_s("F"), "amount" => amount.to_s("F") }
    end
    unless amounts.sum.positive?
      invoice.order_preparation_error = "Der angeforderte Betrag muss insgesamt größer als 0 sein."
      return
    end
    invoice.allocation_mode = "positions"
    invoice.allocation_amount = amounts.sum
    invoice.order_snapshot["allocations"] = allocations
    invoice.invoice_lines.clear
    scope.invoice_lines.each_with_index do |line, index|
      next if amounts[index].zero?
      entry = allocations[index]
      share = entry["mode"] == "percent" ? "#{entry['value'].sub(/\.0+\z/, '')} %" : money(amounts[index])
      details = "<p>Vereinbarter Positionspreis: #{money(line.line_total)}. Davon jetzt: #{ERB::Util.h(share)} = #{money(amounts[index])}.</p>#{line.details_html}"
      invoice.invoice_lines.build(description: "#{invoice.billing_label}: #{line.description}", details: details, quantity: 1, unit_code: "LS", unit_price: amounts[index], tax_rate: 0)
    end
  end

  def money(value)
    "#{ActiveSupport::NumberHelper.number_to_rounded(value, precision: 2, delimiter: ".", separator: ",")} €"
  end

  def requested_amount(invoice, total)
    raw = invoice.allocation_mode == "amount" ? invoice.allocation_amount_before_type_cast : invoice.allocation_percent_before_type_cast
    if raw == "invalid" || raw.nil? || !%w[percent amount].include?(invoice.allocation_mode)
      invoice.order_preparation_error = "Bitte gib einen gültigen Betrag oder Prozentsatz ein."
      return
    end
    value = invoice.allocation_mode == "amount" ? invoice.allocation_amount : invoice.allocation_percent
    amount = invoice.allocation_mode == "amount" ? value : (total * value / 100).round(2)
    if !value.positive? || (invoice.allocation_mode == "percent" && value > 100) || amount <= 0 || amount > total
      invoice.order_preparation_error = "Der angeforderte Betrag muss größer als 0 sein und darf den Gesamtpreis nicht überschreiten."
      return
    end
    amount
  end
end
