class WorkflowsController < ApplicationController
  def edit
    redirect_to new_invoice_path(anchor: "billing-units")
  end

  def update
    input = params.require(:workflow).permit(units: [])
    units = Array(input[:units]).reject(&:blank?).uniq
    unless units.any? && (units - InvoiceLine::UNIT_CODES.keys).empty?
      return render json: { error: "Wähle mindestens eine gültige Einheit." }, status: :unprocessable_entity
    end

    workspace!.update!(workflow_settings: { "units" => units })
    respond_to do |format|
      format.json { render json: { units: units } }
      format.html { redirect_to new_invoice_path(anchor: "billing-units"), notice: "Einheiten gespeichert." }
    end
  end
end
