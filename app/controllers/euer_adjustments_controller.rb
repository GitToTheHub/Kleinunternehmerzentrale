class EuerAdjustmentsController < ApplicationController
  before_action :set_adjustment, only: %i[edit update destroy]

  def new
    requested_year = params[:year].present? ? params[:year].to_i : Date.current.year
    year = EuerFields.supported?(requested_year) ? requested_year : EuerFields::SOURCES.keys.max
    if year != requested_year
      flash.now[:alert] = "Für das angefragte Steuerjahr #{requested_year} sind keine amtlich geprüften EÜR-Formulardaten hinterlegt. Das Formular zeigt ausdrücklich die Anlage EÜR #{year}. Prüfe das ausgewählte Steuerjahr; diese Zuordnung gilt nicht für #{requested_year}."
    end
    @adjustment = EuerAdjustment.new(year: year, field_key: params[:field_key])
  end

  def create
    @adjustment = workspace!.euer_adjustments.new(adjustment_params)
    save_adjustment(:new)
  end

  def edit
  end

  def update
    @adjustment.assign_attributes(adjustment_params)
    save_adjustment(:edit)
  end

  def destroy
    year = @adjustment.year
    @adjustment.destroy!
    redirect_to bookkeeping_entries_path(year: year), notice: "Ergänzung gelöscht.", status: :see_other
  end

  private

  def save_adjustment(template)
    if @adjustment.save
      redirect_to bookkeeping_entries_path(year: @adjustment.year), notice: "Steuerliche Ergänzung gespeichert."
    else
      render template, status: :unprocessable_entity
    end
  end

  def set_adjustment
    @adjustment = (current_workspace ? current_workspace.euer_adjustments : EuerAdjustment.none).find(params[:id])
  end

  def adjustment_params
    params.require(:euer_adjustment).permit(:year, :field_key, :amount, :description)
  end
end
