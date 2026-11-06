class BookkeepingEntriesController < ApplicationController
  before_action :load_report, only: %i[index prepare_euer]
  before_action :set_entry, only: %i[edit update destroy refund create_refund]
  before_action :load_payment_invoices, only: %i[new create edit update]

  def index
    respond_to do |format|
      format.html
      format.csv { send_data @report.csv, filename: "euer-vorbereitung-#{@year}.csv", type: "text/csv; charset=utf-8" }
    end
  end

  def annual
    redirect_to bookkeeping_entries_path(year: selected_year)
  end

  def prepare_euer
  end

  def new
    @choose_kind = !BookkeepingEntry::KINDS.key?(params[:kind]) && params[:invoice_id].blank?
    kind = BookkeepingEntry::KINDS.key?(params[:kind]) ? params[:kind] : "income"
    @entry = BookkeepingEntry.new(paid_on: Date.current, kind: kind, category: kind == "expense" ? nil : BookkeepingEntry::DEFAULT_CATEGORIES[kind])
    if params[:invoice_id].present?
      invoice = current_workspace&.invoices&.find(params[:invoice_id]) || raise(ActiveRecord::RecordNotFound)
      return redirect_to edit_bookkeeping_entry_path(invoice.payment_entry) if invoice.payment_entry
      raise ActiveRecord::RecordNotFound unless invoice.payment_recordable?

      @invoice_payment = true
      @entry.assign_attributes(invoice_payment_attributes(invoice))
      render partial: "invoice_payment_form" if params[:payment_popup] == "1"
    end
  end

  def create
    @invoice_payment = params[:invoice_payment] == "1"
    attributes = if @invoice_payment
      invoice = workspace!.invoices.find(params.require(:bookkeeping_entry)[:invoice_id])
      invoice_payment_attributes(invoice).merge(params.require(:bookkeeping_entry).permit(:paid_on, :payment_account, :cash_usage, :cash_private_amount).to_h).tap do |values|
        values[:amount] = params[:bookkeeping_entry][:amount] if invoice.foreign_currency?
      end
    else
      entry_params
    end
    @entry = workspace!.bookkeeping_entries.new(attributes)
    if save_entry
      if @invoice_payment
        destination = invoices_path(anchor: helpers.dom_id(@entry.invoice))
        message = "#{@entry.invoice.billing_label} als bezahlt markiert. Die Einnahme wurde in der Buchhaltung erfasst."
        if request.format.json?
          flash[:notice] = message
          render json: { location: destination }
        else
          redirect_to destination, notice: message
        end
      else
        redirect_to bookkeeping_entries_path(year: @entry.effective_year), notice: "Vorgang gespeichert."
      end
    else
      if @invoice_payment && params[:payment_popup] == "1"
        render partial: "invoice_payment_form", formats: [ :html ], status: :unprocessable_entity
      else
        render :new, status: :unprocessable_entity
      end
    end
  end

  def edit
  end

  def refund
    @original_entry = @entry
    raise ActiveRecord::RecordNotFound unless @original_entry.refundable?

    @entry = @original_entry.refunds.new(@original_entry.refund_attributes.merge(
      paid_on: Date.current, amount: @original_entry.refundable_amount,
      payment_account: @original_entry.payment_account, description: "Rückzahlung zu: #{@original_entry.description}"))
  end

  def create_refund
    @original_entry = @entry
    @entry = @original_entry.refunds.new(refund_params)
    @entry.assign_attributes(@original_entry.refund_attributes.merge(workspace: @original_entry.workspace))
    if save_entry
      redirect_to bookkeeping_entries_path(year: @entry.effective_year), notice: "Rückzahlung gespeichert und in der EÜR berücksichtigt."
    else
      render :refund, status: :unprocessable_entity
    end
  end

  def update
    @entry.assign_attributes(@entry.original_entry ? refund_params : entry_params)
    @entry.assign_attributes(@entry.original_entry.refund_attributes) if @entry.original_entry
    if save_entry
      redirect_to bookkeeping_entries_path(year: @entry.effective_year), notice: "Vorgang aktualisiert."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    year = @entry.effective_year
    deleted = @entry.workspace.with_lock { @entry.destroy }
    if deleted
      redirect_to bookkeeping_entries_path(year: year), notice: "Zahlung gelöscht.", status: :see_other
    else
      redirect_to bookkeeping_entries_path(year: year), alert: @entry.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private

  def load_report
    @year = selected_year
    @available_years = available_years
    @report = BookkeepingReport.new(current_workspace ? current_workspace.bookkeeping_entries : BookkeepingEntry.none, @year,
      assets: current_workspace ? current_workspace.business_assets : BusinessAsset.none,
      adjustments: current_workspace ? current_workspace.euer_adjustments : EuerAdjustment.none,
      imports: current_workspace ? current_workspace.bookkeeping_imports : BookkeepingImport.none,
      statement: current_workspace&.euer_statements&.find_by(year: @year),
      expense_policy: current_workspace&.euer_expense_policies&.find_by(year: @year))
  end

  def payment_invoices
    return [] unless current_workspace

    current_workspace.invoices.includes(:invoice_lines, :cancellation, :payment_entry).order(issued_on: :desc, id: :desc).select(&:payment_recordable?)
  end

  def load_payment_invoices
    @payment_invoices = payment_invoices.reject { |invoice| invoice.payment_entry && invoice.payment_entry.id != params[:id].to_i }
    if @entry&.invoice && @entry.invoice.workspace_id == current_workspace&.id && @payment_invoices.none? { |invoice| invoice.id == @entry.invoice_id }
      @payment_invoices << @entry.invoice
    end
  end

  def save_entry
    @entry.workspace.with_lock { small_business_category? && @entry.save }
  rescue ActiveRecord::RecordNotUnique
    @entry.errors.add(:invoice, "hat bereits einen erfassten Zahlungseingang")
    false
  end

  def set_entry
    @entry = (current_workspace ? current_workspace.bookkeeping_entries : BookkeepingEntry.none).find(params[:id])
  end

  def available_years
    years = ((Date.current.year - 4)..Date.current.year).to_a
    if current_workspace
      years.concat(current_workspace.bookkeeping_entries.distinct.pluck(:tax_year).compact)
      # Payment years matter for automatically calculated contributions and withdrawals,
      # even when a payment is assigned to a different tax year.
      years.concat(current_workspace.bookkeeping_entries.distinct.pluck(:paid_on).map(&:year))
      years.concat(current_workspace.bookkeeping_imports.distinct.pluck(:year))
      years.concat(current_workspace.euer_adjustments.distinct.pluck(:year))
      years.concat(current_workspace.euer_statements.distinct.pluck(:year))
      years.concat(current_workspace.euer_expense_policies.distinct.pluck(:year))
      years.concat(AssetPrivateUse.where(business_asset_id: current_workspace.business_assets.select(:id)).distinct.pluck(:year))
      years.concat(AssetDepreciation.where(business_asset_id: current_workspace.business_assets.select(:id)).distinct.pluck(:year))
      %i[acquired_on paid_on disposed_on disposal_recognized_on].each do |attribute|
        years.concat(current_workspace.business_assets.distinct.pluck(attribute).compact.map(&:year))
      end
    end
    first_year = years.select { |year| year.between?(1900, Date.current.year) }.min
    (years + (first_year..Date.current.year).to_a + [ @year ]).uniq.sort.reverse
  end

  def selected_year
    value = params[:year].to_s
    value.match?(/\A\d{4}\z/) && value.to_i.between?(1900, 9999) ? value.to_i : Date.current.year
  end

  def small_business_category?
    return true if @entry.original_entry && @entry.effective_category == @entry.original_entry.effective_category

    if @entry.kind == "expense" && params.dig(:bookkeeping_entry, :category) == ""
      @entry.errors.add(:category, "muss ausgewählt werden. Wähle aus, wofür du bezahlt hast.")
      return false
    end

    return true if EuerFields.small_business?(@entry.effective_category) || (!@entry.new_record? && !@entry.category_changed?)

    @entry.errors.add(:category, "ist für die Kleinunternehmer-EÜR nicht vorgesehen")
    false
  end

  def invoice_payment_attributes(invoice)
    { kind: "income", category: "income_small", invoice: invoice, amount: invoice.payment_total_in_euros,
      reference: invoice.invoice_number, description: invoice.payment_description }
  end

  def entry_params
    params.require(:bookkeeping_entry).permit(:paid_on, :kind, :description, :reference, :amount, :category,
      :deductible_percent, :business_percent, :usage_notes, :payment_account, :reversal, :tax_year, :invoice_id, :cash_usage, :cash_private_amount)
  end

  def refund_params
    params.require(:bookkeeping_entry).permit(:paid_on, :description, :reference, :amount, :payment_account, :tax_year, :cash_usage, :cash_private_amount)
  end
end
