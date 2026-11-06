class EuerStatementsController < ApplicationController
  def edit
    @year = selected_year
    @statement = current_workspace&.euer_statements&.find_by(year: @year) || EuerStatement.new(year: @year)
    existing = (current_workspace&.bookkeeping_imports&.find_by(year: @year)&.details || {}).merge(@statement.details)
    suggestions = current_workspace&.business_profile&.euer_details || {}
    suggestions.delete("taxpayer_name") if existing.key?("taxpayer_name") || existing.key?("first_name")
    @suggested_details = suggestions.except(*existing.keys)
    @statement.details = @suggested_details.merge(existing)
    load_report
  end

  def update
    @year = selected_year
    workspace = workspace!
    saved = workspace.with_lock do
      @statement = workspace.euer_statements.find_or_initialize_by(year: @year)
      @statement.update(details: params.require(:euer_statement).permit(details: EuerForm::DETAILS.keys).fetch(:details, {}).to_h)
    end
    if saved
      redirect_to edit_euer_statement_path(year: @year), notice: "EÜR-Betriebsangaben gespeichert."
    else
      load_report
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def selected_year
    year = params[:year].present? ? params[:year].to_i : Date.current.year
    raise ActiveRecord::RecordNotFound unless EuerFields.supported?(year)

    year
  end

  def load_report
    @report = BookkeepingReport.new(current_workspace ? current_workspace.bookkeeping_entries : BookkeepingEntry.none, @year,
      assets: current_workspace ? current_workspace.business_assets : BusinessAsset.none,
      adjustments: current_workspace ? current_workspace.euer_adjustments : EuerAdjustment.none,
      imports: current_workspace ? current_workspace.bookkeeping_imports : BookkeepingImport.none, statement: @statement,
      expense_policy: current_workspace&.euer_expense_policies&.find_by(year: @year))
  end
end
