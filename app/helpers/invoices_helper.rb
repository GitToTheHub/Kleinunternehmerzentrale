module InvoicesHelper
  def invoice_order_payment_summary(invoice)
    return unless invoice.staged_invoice? && !invoice.cancellation? && !invoice.cancellation && invoice.order_total

    paid_invoices = invoice.order_invoices.where(cancelled_invoice_id: nil).includes(:cancellation, payment_entry: :refunds)
      .reject(&:cancellation).select { |item| item.payment_entry && item.payment_entry.amount > item.payment_entry.refunds.sum(&:amount) }
    paid = paid_invoices.sum { |item| item.payment_entry.amount - item.payment_entry.refunds.sum(&:amount) }
    { total: invoice.order_total, paid: paid, paid_invoices: paid_invoices, outstanding: [ invoice.order_total - paid, 0.to_d ].max }
  end

  def invoice_payment_action(_invoice)
    "Rechnung als bezahlt markieren"
  end

  def invoice_payment_title(invoice)
    invoice_payment_action(invoice)
  end

  def invoice_payment_amount_label(invoice)
    invoice.final_invoice? ? "Restbetrag" : "Betrag"
  end

  INVOICE_FORM_HINTS = {
    "regular" => "Rechne eine Lieferung oder Leistung vollständig ab.",
    "advance" => "Fordere eine Zahlung im Voraus an, bevor du die Lieferung oder Leistung erbracht hast. Die Anzahlung wird später in der Schlussrechnung angerechnet.",
    "progress" => "Rechne bereits erbrachte Teile einer Lieferung oder Leistung ab. Der Auftrag läuft noch. Erhaltene Zahlungen werden später in der Schlussrechnung angerechnet.",
    "final" => "Rechne den vollständigen Auftrag ab. Bereits erhaltene Anzahlungen und Abschläge werden abgezogen."
  }.freeze

  def invoice_scope_positions?(invoice)
    invoice.partial_invoice? && !invoice.cancellation? && invoice.order_snapshot["show_scope_positions"] == true
  end

  def invoice_display_lines(invoice)
    return invoice.invoice_lines unless invoice_scope_positions?(invoice)

    invoice.order_snapshot.fetch("lines").map { |attributes| InvoiceLine.new(attributes.slice(*InvoiceLine::COPIED_ATTRIBUTES)) }
  end

  ACTION_ICON_PATHS = {
    save: "M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h12l4 4v12a2 2 0 0 1-2 2ZM17 21v-8H7v8M7 3v5h8V3",
    lock: "M6 10V7a6 6 0 0 1 12 0v3M4 10h16v12H4ZM12 14v4",
    preview: "M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7ZM15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0",
    later: "M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0M12 7v5l3 2",
    delete: "M3 6h18M9 6V4h6v2M5 6l1 14h12l1-14M10 10v6M14 10v6",
    cancel: "m6 6 12 12M6 18 18 6"
  }.freeze

  def invoice_action_icon(name, **options)
    content_tag(:svg, tag.path(d: ACTION_ICON_PATHS.fetch(name)),
      **options, class: "invoice-action-icon", viewBox: "0 0 24 24", fill: "none", stroke: "currentColor",
      "stroke-width" => 1.8, "stroke-linecap" => "round", "stroke-linejoin" => "round",
      "aria-hidden" => true, focusable: false)
  end

  CUSTOMER_CHANGE_LABELS = {
    name: "Firmenname / Name", street: "Straße", postal_code: "Postleitzahl", city: "Ort", country: "Land",
    email: "E-Mail-Adresse", contact_name: "Ansprechpartner", invoice_abbreviation: "Kundenkürzel",
    leitweg_id: "Leitweg-ID", payment_terms: "Zahlungshinweis", hourly_rate: "Individueller Stundensatz", payment_due_days: "Zahlungsfrist"
  }.freeze

  def customer_invoice_changes(invoice)
    return {} unless invoice.customer

    invoice.customer.attributes_from_invoice(invoice).filter_map do |key, value|
      stored = invoice.customer[key]
      next if stored.to_s == value.to_s

      display = ->(entry) do
        if entry.blank?
          "nicht hinterlegt"
        elsif key == :hourly_rate
          "#{number_to_currency(entry, locale: :de)} pro Stunde"
        elsif key == :payment_due_days
          "#{entry} Tage"
        else
          entry.to_s
        end
      end
      [ key, "#{CUSTOMER_CHANGE_LABELS.fetch(key)}: #{display.call(stored)} → #{display.call(value)}" ]
    end.to_h
  end

  FIELD_ICON_PATHS = {
    settings: "M9.5 1.2h5l.5 3 2 1.2 2.8-1 2.5 4.4-2.3 2v2.4l2.3 2-2.5 4.4-2.8-1-2 1.2-.5 3h-5l-.5-3-2-1.2-2.8 1-2.5-4.4 2.3-2v-2.4l-2.3-2 2.5-4.4 2.8 1L9 5l.5-3ZM15.5 12a3.5 3.5 0 1 1-7 0 3.5 3.5 0 0 1 7 0Z",
    person: "M20 21v-2a7 7 0 0 0-14 0v2M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z",
    email: "M3 5h18v14H3ZM3 5l9 7 9-7",
    phone: "M5 3h4l2 5-3 2a16 16 0 0 0 6 6l2-3 5 2v4c0 1-1 2-2 2A18 18 0 0 1 3 5c0-1 1-2 2-2Z",
    address: "M20 10c0 6-8 11-8 11S4 16 4 10a8 8 0 1 1 16 0ZM15 10a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z",
    globe: "M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0ZM2 12h20M12 2a20 20 0 0 1 0 20 20 20 0 0 1 0-20Z",
    calendar: "M3 5h18v16H3ZM7 3v4M17 3v4M3 11h18M7 15h2M13 15h2",
    number: "M9 3 7 21M17 3l-2 18M3 9h18M2 15h18",
    bank: "M3 9h18L12 3ZM5 10v9M12 10v9M19 10v9M3 21h18",
    document: "M5 3h10l4 4v14H5ZM15 3v5h4M8 12h8M8 16h8",
    packages: "m12 2 5 2.5v6L12 13l-5-2.5v-6ZM7 4.5 12 7l5-2.5M12 7v6M7 10l5 2.5v6L7 21l-5-2.5v-6ZM2 12.5 7 15l5-2.5M7 15v6M17 10l5 2.5v6L17 21l-5-2.5v-6ZM12 12.5 17 15l5-2.5M17 15v6",
    quantity: "M4 4h6v6H4ZM14 4h6v6h-6ZM4 14h6v6H4ZM14 14h6v6h-6Z",
    clock: "M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0ZM12 6v6l4 2",
    money: "M16 6a4 4 0 1 1-8 0 4 4 0 0 1 8 0ZM10.5 17a4 4 0 1 1-8 0 4 4 0 0 1 8 0ZM21.5 17a4 4 0 1 1-8 0 4 4 0 0 1 8 0ZM12 4.5v3M6.5 15.5v3M17.5 15.5v3"
  }.freeze

  def invoice_money(value, invoice)
    number_to_currency(value, unit: invoice.currency == "EUR" ? "€" : invoice.currency, format: "%n %u", locale: :de)
  end

  def invoice_field_icon(field)
    name = field.to_s
    kind = case name
    when "settings" then :settings
    when "clock" then :clock
    when "packages" then :packages
    when /email/ then :email
    when /phone/ then :phone
    when /country|domain/ then :globe
    when /_on$/ then :calendar
    when /street|postal_code|city/ then :address
    when /iban|bic/ then :bank
    when /unit_price|currency|exchange_rate/ then :money
    when /quantity|unit_code/ then :quantity
    when /number|abbreviation|tax_identifier|leitweg/ then :number
    when /name|customer/ then :person
    else :document
    end
    content_tag(:svg, tag.path(d: FIELD_ICON_PATHS.fetch(kind)), class: "field-label__icon",
      viewBox: "0 0 24 24", width: 18, height: 18, fill: "none", stroke: "currentColor",
      "stroke-width": 1.6, "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": true, focusable: false)
  end

  def invoice_field_label(form, field, text, options = {})
    options = options.dup
    text_data = options.delete(:data)
    options[:class] = [ options[:class], "field-label" ].compact.join(" ")
    form.label(field, options) do
      safe_join([ invoice_field_icon(field), content_tag(:span, text, data: text_data) ])
    end
  end
end
