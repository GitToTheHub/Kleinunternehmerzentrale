class BookkeepingImportsController < ApplicationController
  def new
    requested_year = params[:year].present? ? params[:year].to_i : Date.current.year
    year = EuerFields.supported?(requested_year) ? requested_year : EuerFields::SOURCES.keys.max
    if year != requested_year
      flash.now[:alert] = "Für das angefragte Steuerjahr #{requested_year} sind keine amtlich geprüften EÜR-Formulardaten hinterlegt. Das Formular zeigt ausdrücklich die Anlage EÜR #{year}. Prüfe das ausgewählte Steuerjahr; diese Zuordnung gilt nicht für #{requested_year}."
    end
    @import = BookkeepingImport.new(year: year)
    @values = {}
  end

  def template
    send_data EuerTotalsImport.template, filename: "euer-summen-vorlage.csv", type: "text/csv; charset=utf-8"
  end

  def preview
    @values = import_params.to_h.fetch("amounts", {})
    @import = workspace!.bookkeeping_imports.new(import_params.except(:amounts))
    upload = params[:file]
    if params[:review_token].present?
      payload = verifier.verified(params[:review_token], purpose: current_workspace.id.to_s)
      raise EuerTotalsImport::InvalidFile, "Die Vorschau ist abgelaufen oder ungültig. Bitte lade die Datei erneut hoch." unless payload

      @import = current_workspace.bookkeeping_imports.new(payload)
      @import.assign_attributes(import_params.slice(:covered_through, :source))
      @values = @import.amounts.transform_values { |amount| amount.tr(".", ",") }
    elsif params[:input_mode] == "pdf"
      raise EuerTotalsImport::InvalidFile, "Wähle eine sevdesk-EÜR als PDF aus." unless upload.is_a?(ActionDispatch::Http::UploadedFile)

      parsed = SevdeskEuerImport.pdf(upload)
      @import.assign_attributes(year: parsed.year, covered_through: parsed.covered_through, amounts: parsed.amounts, notes: parsed.notes)
      @import.source = "sevdesk-EÜR (PDF)" if @import.source.blank?
      @values = parsed.amounts.transform_values { |amount| amount.tr(".", ",") }
    elsif params[:input_mode] == "csv" || upload.present?
      raise EuerTotalsImport::InvalidFile, "Wähle eine CSV-Datei aus." unless upload.is_a?(ActionDispatch::Http::UploadedFile)

      @import.amounts = EuerTotalsImport.csv(upload)
    else
      @import.amounts = EuerTotalsImport.manual(@values)
    end
    if @import.valid?
      @token = verifier.generate(@import.attributes.slice("year", "covered_through", "source", "amounts", "assets_managed_separately", "details", "notes"), purpose: current_workspace.id.to_s, expires_in: 30.minutes)
      render :preview
    else
      render :new, status: :unprocessable_entity
    end
  rescue EuerTotalsImport::InvalidFile => error
    @import.errors.add(:base, error.message)
    render :new, status: :unprocessable_entity
  end

  def create
    payload = verifier.verified(params[:token], purpose: current_workspace&.id.to_s)
    return redirect_to new_bookkeeping_import_path, alert: "Die Vorschau ist abgelaufen oder ungültig. Bitte erstelle sie erneut." unless payload && current_workspace

    @import = current_workspace.bookkeeping_imports.new(payload)
    current_workspace.with_lock do
      if params[:confirmed] != "1"
        @import.errors.add(:base, "Bitte bestätige den Abgleich mit deiner bisherigen EÜR.")
      elsif @import.save
        return redirect_to bookkeeping_entries_path(year: @import.year), notice: "Die bisherigen EÜR-Summen wurden übernommen."
      end
    end
    @token = params[:token]
    render :preview, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    redirect_to new_bookkeeping_import_path, alert: "Für dieses Steuerjahr wurden bereits EÜR-Summen übernommen."
  end

  def show
    @import = scoped_imports.find(params[:id])
  end

  def destroy
    import = scoped_imports.find(params[:id])
    year = import.year
    import.workspace.with_lock { import.destroy! }
    redirect_to bookkeeping_entries_path(year: year), notice: "Die Übernahme wurde entfernt. Später erfasste Vorgänge bleiben erhalten.", status: :see_other
  end

  private

  def verifier = Rails.application.message_verifier(:euer_totals_import)
  def scoped_imports = current_workspace ? current_workspace.bookkeeping_imports : BookkeepingImport.none

  def import_params
    params.require(:bookkeeping_import).permit(:year, :covered_through, :source, :assets_managed_separately, details: EuerForm::DETAILS.keys, amounts: EuerFields::DEFINITIONS.keys)
  end
end
