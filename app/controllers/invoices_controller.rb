class InvoicesController < ApplicationController
  before_action :set_invoice, only: %i[show xrechnung cancel]

  def index
    @invoices = current_workspace ? current_workspace.invoices.includes(:invoice_lines).order(issued_on: :desc, id: :desc) : Invoice.none
  end

  def new
    load_customers
    @invoice = Invoice.new(
      { issued_on: Date.current, service_on: Date.current, payment_due_on: Date.current + 14, buyer_country: "DE" }.merge(@profile.invoice_attributes)
    )
    if (original = copy_source)
      @invoice.assign_attributes(original.attributes.slice(*Invoice::COPIED_ATTRIBUTES).except("service_on", "service_until_on"))
      original.invoice_lines.each { |line| @invoice.invoice_lines.build(line.attributes.slice(*InvoiceLine::COPIED_ATTRIBUTES)) }
    else
      @invoice.invoice_lines.build(quantity: 1, unit_price: 0, unit_code: "C62", tax_rate: 19)
    end
  end

  def create
    @invoice = workspace!.invoices.new(invoice_params)

    if @invoice.save
      flash[:first_invoice] = true if @invoice.workspace.invoices.one?
      redirect_to @invoice, notice: "Deine Rechnung wurde erstellt."
    else
      load_customers
      render :new, status: :unprocessable_entity
    end
  end

  def show
  end

  # Zeigt die Rechnung wie gedruckt an, ohne sie zu speichern.
  def preview
    workspace = current_workspace || Workspace.new
    @invoice = workspace.invoices.new(invoice_params)
    return render :preview_errors, status: :unprocessable_entity unless @invoice.valid?

    @invoice.invoice_number = workspace.invoices.next_invoice_number(@invoice.issued_on)
    @preview = true
    render :show
  end

  # Hebt eine Rechnung mit einer Stornorechnung auf. Die Originalrechnung bleibt unverändert.
  def cancel
    cancellation = @invoice.build_cancellation
    if cancellation.save
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

  def copy_source
    current_workspace&.invoices&.includes(:invoice_lines)&.find_by(id: params[:copy_from])
  end

  def load_customers
    @profile = current_workspace ? BusinessProfile.for(current_workspace) : BusinessProfile.new(country: "DE")
    @customers = current_workspace ? current_workspace.customers.alphabetical : Customer.none
  end

  def set_invoice
    raise ActiveRecord::RecordNotFound unless current_workspace

    @invoice = current_workspace.invoices.includes(:invoice_lines).find(params[:id])
  end

  def invoice_params
    params.require(:invoice).permit(
      :issued_on, :service_on, :service_until_on, :service_period, :seller_name, :seller_street, :seller_postal_code,
      :seller_city, :seller_country, :seller_email, :seller_tax_identifier,
      :buyer_name, :buyer_street, :buyer_postal_code,
      :buyer_city, :buyer_country, :buyer_email, :buyer_leitweg_id, :buyer_order_number, :payment_terms, :tax_mode, :iban, :bic, :payment_due_on,
      invoice_lines_attributes: %i[id description details quantity unit_price unit_code tax_rate _destroy]
    )
  end
end
