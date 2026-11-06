class SalesDocumentsController < ApplicationController
  include InvoiceInput
  before_action :set_document, only: %i[show edit update accept]

  def index
    @documents = current_workspace ? current_workspace.sales_documents.order(document_date: :desc, id: :desc) : SalesDocument.none
  end

  def new
    @document = (current_workspace || Workspace.new).sales_documents.new(kind: params[:kind] == "order" ? "order" : "offer", document_date: Date.current)
    prepare_form
  end

  def create
    workspace = workspace!
    if params[:kind] == "order" && params[:source_offer_id].present?
      offer = workspace.sales_documents.where(kind: "offer").find(params[:source_offer_id])
      return redirect_to offer.accept!, notice: "Das Angebot wurde als Auftrag übernommen."
    end
    @document = workspace.sales_documents.new(kind: params[:kind] == "order" ? "order" : "offer", document_date: form_document_date, data: SalesDocument.input_data(invoice_params))
    @document.invoice_number_last = params.dig(:invoice, :invoice_number_last)
    saved = workspace.with_lock { @document.save }
    if saved
      redirect_to @document, notice: "#{@document.label} gespeichert."
    else
      prepare_form
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @invoice = @document.invoice_view
    @invoice.valid?
  end

  def edit
    return redirect_to @document, alert: "Dieser Stand bleibt unverändert, weil er bereits angenommen oder abgerechnet wurde." unless @document.editable?
    prepare_form
    render :new
  end

  def update
    @document.invoice_number_last = params.dig(:invoice, :invoice_number_last)
    saved = current_workspace.with_lock do
      @document.update(document_date: form_document_date, data: SalesDocument.input_data(invoice_params), lock_version: params[:lock_version])
    end
    if saved
      redirect_to @document, notice: "#{@document.label} gespeichert."
    else
      prepare_form
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::StaleObjectError
    redirect_to @document, alert: "Dieser Eintrag wurde inzwischen in einem anderen Tab geändert. Bitte lade den aktuellen Stand."
  end

  def accept
    raise ActiveRecord::RecordNotFound unless @document.offer?
    order = @document.accept!
    redirect_to order, notice: "Das Angebot wurde als Auftrag übernommen."
  end

  def next_number
    workspace = current_workspace || Workspace.new
    document = if params[:document_id].present?
      workspace.sales_documents.find(params[:document_id])
    else
      workspace.sales_documents.new(kind: params[:billing_kind] == "order" ? "order" : "offer")
    end
    if document.number_unchanged?(params[:invoice_number_format], params[:invoice_number_last])
      return render json: { invoice_number: document.document_number, sequence: document.number_sequence }
    end
    number, sequence, daily = document.number_generator(date: Date.iso8601(params[:issued_on].to_s), format: params[:invoice_number_format],
      abbreviation: params[:buyer_abbreviation], last: params[:invoice_number_last]).number_and_sequence
    render json: { invoice_number: number, sequence: sequence || daily }
  rescue InvoiceNumber::Invalid => error
    render json: { error: error.message, field: error.field, sequence: error.sequence }, status: :unprocessable_entity
  rescue Date::Error
    render json: { error: "Bitte gib ein gültiges Datum ein." }, status: :unprocessable_entity
  end

  private

  def set_document
    @document = current_workspace&.sales_documents&.find(params[:id]) || raise(ActiveRecord::RecordNotFound)
  end

  def form_document_date
    params[:document_date].presence || params.dig(:invoice, :issued_on)
  end

  def prepare_form
    @available_offers = if @document.new_record? && @document.order? && current_workspace
      current_workspace.sales_documents.where(kind: "offer").where.missing(:accepted_order).order(document_date: :desc, id: :desc)
    else
      SalesDocument.none
    end
    @customers = current_workspace ? current_workspace.customers.alphabetical : Customer.none
    @profile = current_workspace ? BusinessProfile.for(current_workspace) : BusinessProfile.new(country: "DE")
    defaults = @profile.invoice_attributes.merge(issued_on: @document.document_date, seller_hourly_rate: @profile.hourly_rate, buyer_country: "DE", currency: "EUR", tax_mode: "small_business")
    @invoice = @document.workspace.invoices.new(defaults.merge(@document.data).merge(issued_on: @document.document_date, invoice_number_format: @document.number_format))
    @invoice.invoice_number_last = @document.invoice_number_last
    @invoice.invoice_lines.build(quantity: 1, unit_price: 0, unit_code: current_workspace&.default_invoice_unit || "HUR", tax_rate: 0) if @invoice.invoice_lines.empty?
  end
end
