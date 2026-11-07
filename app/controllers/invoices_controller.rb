class InvoicesController < ApplicationController
  include InvoiceInput
  before_action :set_invoice, only: %i[show xrechnung cancel]
  before_action :require_small_business_form, only: %i[create preview save_draft]

  SMALL_BUSINESS_ONLY_MESSAGE = "Hier können derzeit nur Rechnungen nach der Kleinunternehmerregelung erstellt und bearbeitet werden. Bereits gespeicherte Rechnungen und Entwürfe mit Regelbesteuerung bleiben unverändert.".freeze
  rate_limit to: 20, within: 10.minutes, only: :lookup_customer_imprint,
    with: -> { render json: { error: "Zu viele Anfragen. Bitte warte kurz." }, status: :too_many_requests }

  def index
    @invoices = current_workspace ? current_workspace.invoices.includes(:invoice_lines, :cancellation, :cancelled_invoice, :corrected_invoice, :payment_entry).order(issued_on: :desc, id: :desc) : Invoice.none
    @billing_overview = InvoiceBillingOverview.call(@invoices)
    @settlement_groups = InvoiceSettlementSelection.groups(current_workspace)
    @invoice_drafts = current_workspace ? current_workspace.invoice_drafts.active.order(updated_at: :desc, id: :desc) : InvoiceDraft.none
  end

  def new
    load_customers
    @draft = if params[:draft_id].present?
      current_workspace&.invoice_drafts&.active&.find(params[:draft_id]) || raise(ActiveRecord::RecordNotFound)
    else
      InvoiceDraft.new(form_token: SecureRandom.uuid)
    end
    @invoice = (current_workspace || Workspace.new).invoices.new(
      { issued_on: Date.current, service_on: Date.current, payment_due_on: Date.current + 14, buyer_country: "DE" }.merge(@profile.invoice_attributes).merge(tax_mode: "small_business")
    )
    if (original = copy_source)
      @invoice.settlement_invoice_ids = original.order_snapshot["settlement_invoice_ids"] || [] if original.final_invoice? && original.cancellation
      @invoice.assign_attributes(original.attributes.slice(*Invoice::COPIED_ATTRIBUTES).except("service_on", "service_until_on"))
      @invoice.sales_document = original.sales_document if original.sales_document_id
      if original.sales_document_id
        @invoice.order_based = true
        @invoice.allocation_basis = original.position_based? ? "positions" : "total"
        @invoice.allocation_mode = original.position_based? ? "percent" : original.allocation_mode || "percent"
        @invoice.position_allocations = (original.order_snapshot["allocations"] || []).to_h do |entry|
          values = entry["mode"] == "allocated" ? { "mode" => "amount", "value" => entry["amount"] } : entry.slice("mode", "value")
          [ entry["source_index"].to_s, values ]
        end
        @invoice.allocation_percent = original.allocation_percent || 50
        @invoice.allocation_amount = original.allocation_amount
      end
      @invoice.payment_due_on = if original.payment_due_on && original.issued_on
        @invoice.issued_on + (original.payment_due_on - original.issued_on).to_i
      end
      @invoice.corrected_invoice = original if original.cancellation && !original.cancellation?
      original.invoice_lines.each { |line| @invoice.invoice_lines.build(line.attributes.slice(*InvoiceLine::COPIED_ATTRIBUTES)) }
      if original.staged_invoice? && original.cancellation
        @invoice.billing_kind = original.billing_kind
        @invoice.billing_root_id = original.billing_root_id_for_order
      end
    elsif params[:sales_document_id].present?
      document = current_workspace&.sales_documents&.find(params[:sales_document_id]) || raise(ActiveRecord::RecordNotFound)
      raise ActiveRecord::RecordNotFound unless document.order?
      @invoice.assign_attributes(document.invoice_attributes.except("invoice_lines_attributes").merge("service_on" => document.data["service_on"].presence || Date.current))
      @invoice.sales_document = document
      customer = current_workspace.customers.find_by(id: document.data["customer_id"])
      @invoice.payment_due_on = customer&.payment_due_days && @invoice.issued_on + customer.payment_due_days
      @invoice.order_based = true
      @invoice.allocation_mode = "percent"
      @invoice.allocation_percent = 50
      @invoice.billing_kind = params[:billing_kind].in?(%w[regular advance progress final]) ? params[:billing_kind] : "regular"
    elsif params[:billing_root_id].present?
      root = current_workspace&.invoices&.find(params[:billing_root_id]) || raise(ActiveRecord::RecordNotFound)
      @invoice.assign_attributes(root.attributes.slice(*Invoice::COPIED_ATTRIBUTES).except("service_on", "service_until_on"))
      @invoice.payment_terms = root.payment_terms
      @invoice.billing_root_id = root.billing_root_id_for_order
      @invoice.billing_kind = params[:billing_kind].in?(%w[advance progress final]) ? params[:billing_kind] : "progress"
    elsif @draft.persisted?
      @invoice.assign_attributes(@draft.data.reverse_merge("payment_due_on" => nil))
    else
      @invoice.order_based = true
      @invoice.billing_kind = "final" if params[:billing_kind] == "final"
      @invoice.allocation_mode = "percent"
      @invoice.allocation_percent = 50
      @invoice.invoice_lines.build(quantity: 1, unit_price: ((current_workspace&.default_invoice_unit || "HUR") == "HUR" ? @invoice.seller_hourly_rate || 0 : 0), unit_code: (current_workspace&.default_invoice_unit || "HUR"), tax_rate: 0)
    end
    if @invoice.sales_document_id
      document = current_workspace&.sales_documents&.find(@invoice.sales_document_id) || raise(ActiveRecord::RecordNotFound)
      raise ActiveRecord::RecordNotFound unless document.order?
      @invoice.sales_document = document
      @invoice.invoice_lines.clear
      document.invoice_attributes.fetch("invoice_lines_attributes").each_value { |line| @invoice.invoice_lines.build(line) }
    end
    prepare_position_allocation_fields(@draft.data) if @draft.persisted?
    if @invoice.standard_taxed?
      return redirect_to invoices_path, alert: SMALL_BUSINESS_ONLY_MESSAGE
    end
    @invoice.invoice_lines.build(quantity: 1, unit_price: ((current_workspace&.default_invoice_unit || "HUR") == "HUR" ? @invoice.seller_hourly_rate || 0 : 0), unit_code: (current_workspace&.default_invoice_unit || "HUR"), tax_rate: 0) if @invoice.invoice_lines.empty?
  end

  def create
    workspace = workspace!
    workspace.with_lock do
      @draft = draft_for_write(workspace)
      @invoice = OrderInvoicePreparation.new(workspace, invoice_params).call
      @invoice.record_initial_payment = true
      @created = @invoice.save
      @draft.close!(:completed) if @created
    end

    if @created
      flash[:first_invoice] = true if @invoice.workspace.invoices.one?
      redirect_to @invoice, notice: "Deine Rechnung wurde erstellt."
    else
      if @invoice.sales_document || (@invoice.partial_invoice? && @invoice.order_based?)
        # Re-render the full entered scope, never the calculated advance as a new scope.
        messages = @invoice.errors.full_messages
        document = @invoice.sales_document if @invoice.sales_document&.persisted?
        @invoice = workspace.invoices.new(invoice_params)
        if document
          @invoice.sales_document = document
          @invoice.invoice_lines.clear
          document.invoice_attributes.fetch("invoice_lines_attributes").each_value { |line| @invoice.invoice_lines.build(line) }
        end
        messages.each { |message| @invoice.errors.add(:base, message) }
      end
      prepare_position_allocation_fields(invoice_params.to_h)
      load_customers
      render :new, status: :unprocessable_entity
    end
  end

  def show
    if @invoice.cancellation
      @correction_invoice = @invoice.workspace.invoices.where(corrected_invoice_id: @invoice.id).order(created_at: :desc, id: :desc).first
      @correction_draft = @invoice.workspace.invoice_drafts.active.order(updated_at: :desc, id: :desc).detect do |draft|
        draft.data["corrected_invoice_id"].to_s == @invoice.id.to_s
      end
    end
  end

  def exchange_rate
    render json: ExchangeRateLookup.new(currency: params[:currency], date: params[:issued_on]).call
  rescue ExchangeRateLookup::LookupError => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def next_number
    date = Date.iso8601(params[:issued_on].to_s)
    invoices = current_workspace ? current_workspace.invoices : Invoice.none
    number, sequence, daily_sequence = InvoiceNumber.new(invoices, date: date,
      format: (params.key?(:invoice_number_format) ? params[:invoice_number_format] : current_workspace&.business_profile&.invoice_number_format || InvoiceNumber::DEFAULT_FORMAT),
      billing_kind: params[:billing_kind].presence || "regular", buyer_abbreviation: params[:buyer_abbreviation], sequence_start: params[:invoice_number_start], last_sequence: params[:invoice_number_last]).number_and_sequence
    render json: { invoice_number: number, sequence: sequence || daily_sequence }
  rescue InvoiceNumber::Invalid => error
    render json: { error: error.message, field: error.field, sequence: error.sequence }, status: :unprocessable_entity
  rescue Date::Error
    render json: { error: "Bitte gib ein gültiges Rechnungsdatum ein." }, status: :unprocessable_entity
  end

  # Speichert den aktuellen Formularstand als Entwurf und öffnet dessen dauerhafte Vorschau.
  def preview
    workspace = current_workspace || Workspace.new
    @invoice = OrderInvoicePreparation.new(workspace, invoice_params).call
    @invoice.record_initial_payment = true
    return render :preview_errors, status: :unprocessable_entity unless @invoice.valid?

    @draft = persist_draft!
    redirect_to draft_preview_invoices_path(draft_id: @draft.id), status: :see_other
  end

  def draft_preview
    @draft = current_workspace&.invoice_drafts&.active&.find(params[:draft_id]) || raise(ActiveRecord::RecordNotFound)
    @embedded_preview = params[:embedded] == "1"
    workspace = @draft.workspace
    @invoice = OrderInvoicePreparation.new(workspace, @draft.data.reverse_merge("payment_due_on" => nil)).call
    return render :preview_errors, layout: (@embedded_preview ? "invoice_preview" : "application"), status: :unprocessable_entity unless @invoice.valid?

    @preview = true
    render :show, layout: (@embedded_preview ? "invoice_preview" : "application")
  end

  def lookup_customer_imprint
    render json: ImprintLookup.new(params.require(:domain)).call
  rescue ImprintLookup::LookupError => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def save_draft
    @draft = persist_draft!
    render json: { saved_at: @draft.updated_at.iso8601, draft_id: @draft.id,
                   save_url: save_invoice_draft_invoices_path(draft_id: @draft.id),
                   delete_url: discard_invoice_draft_invoices_path(draft_id: @draft.id),
                   edit_url: edit_draft_invoices_path(draft_id: @draft.id),
                   preview_url: draft_preview_invoices_path(draft_id: @draft.id) }
  end

  def discard_draft
    raise ActiveRecord::RecordNotFound if params[:draft_id].blank? && params[:form_token].blank?
    if current_workspace
      current_workspace.with_lock { draft_for_write(current_workspace).close!(:discarded) }
    elsif InvoiceDraft.exists?(id: params[:draft_id])
      raise ActiveRecord::RecordNotFound
    end
    respond_to do |format|
      format.html { redirect_to invoices_path, notice: "Der Rechnungsentwurf wurde verworfen." }
      format.json { head :no_content }
    end
  end

  # Hebt eine Rechnung mit einer Stornorechnung auf. Die Originalrechnung bleibt unverändert.
  def cancel
    cancellation = @invoice.build_cancellation
    saved = @invoice.workspace.with_lock { cancellation.save }
    if saved
      redirect_to new_invoice_path(copy_from: @invoice.id),
        notice: "Die Rechnung #{@invoice.invoice_number} ist storniert (Stornorechnung #{cancellation.invoice_number}). Hier kannst du die korrigierte Rechnung erstellen."
    else
      redirect_to @invoice, alert: cancellation.errors.full_messages.to_sentence
    end
  end

  def xrechnung
    if @invoice.seller_email.blank? || @invoice.buyer_email.blank?
      redirect_to @invoice, alert: "Für eine XRechnung benötigst du eine E-Mail-Adresse für dich und deine Kundin oder deinen Kunden."
      return
    end

    xml = XrechnungGenerator.new(@invoice).call
    send_data xml, filename: "#{@invoice.invoice_number}.xml", type: "application/xml; charset=utf-8", disposition: :attachment
  end

  private

  def require_small_business_form
    mode = params.dig(:invoice, :tax_mode)
    drafts = current_workspace&.invoice_drafts&.active
    draft = if params[:draft_id].present?
      drafts&.find_by(id: params[:draft_id])
    elsif params[:form_token].present?
      drafts&.find_by(form_token: params[:form_token])
    end
    return unless (mode.present? && mode != "small_business") || draft&.data&.fetch("tax_mode", nil) == "standard"

    render json: { error: SMALL_BUSINESS_ONLY_MESSAGE }, status: :unprocessable_entity
  end

  def draft_for_write(workspace)
    draft = if params[:draft_id].present?
      raise ActiveRecord::RecordNotFound unless params[:draft_id].to_s.match?(/\A[1-9][0-9]*\z/)
      workspace.invoice_drafts.find(params[:draft_id])
    else
      token = params[:form_token].presence || SecureRandom.uuid
      workspace.invoice_drafts.find_or_initialize_by(form_token: token)
    end
    raise ActiveRecord::RecordNotFound unless draft.active?
    draft
  end

  def persist_draft!
    workspace = workspace!
    workspace.with_lock do
      draft_for_write(workspace).tap do |draft|
        attributes = { data: draft_attributes }
        attributes[:resume_section] = params[:resume_section] if InvoiceDraft::RESUME_SECTIONS.include?(params[:resume_section])
        draft.update!(attributes)
      end
    end
  end

  def copy_source
    current_workspace&.invoices&.includes(:invoice_lines)&.find_by(id: params[:copy_from])
  end

  def prepare_position_allocation_fields(source)
    return if @invoice.sales_document_id || @invoice.position_allocations.blank?
    lines = source["invoice_lines_attributes"]
    return unless lines.is_a?(Hash)
    keys = lines.reject { |_key, line| ActiveModel::Type::Boolean.new.cast(line["_destroy"]) }.keys
    values = @invoice.position_allocations
    @invoice.position_allocations = keys.each_with_index.to_h { |key, index| [ index.to_s, values[key.to_s] ] }.compact
  end

  def load_customers
    @settlement_groups = InvoiceSettlementSelection.groups(current_workspace)
    @profile = current_workspace ? BusinessProfile.for(current_workspace) : BusinessProfile.new(country: "DE")
    @customers = current_workspace ? current_workspace.customers.alphabetical : Customer.none
  end

  def set_invoice
    raise ActiveRecord::RecordNotFound unless current_workspace

    @invoice = current_workspace.invoices.includes(:invoice_lines).find(params[:id])
  end


  def draft_attributes
    invoice_params.to_h.tap do |attributes|
      attributes["tax_mode"] = "small_business"
      # Empty or omitted optional dates mean no deadline, including when reopening a draft.
      attributes["payment_due_on"] = attributes["payment_due_on"].presence
      attributes.fetch("invoice_lines_attributes", {}).each_value do |line|
        line.delete("id")
        line["tax_rate"] = "0"
      end
    end
  end
end
