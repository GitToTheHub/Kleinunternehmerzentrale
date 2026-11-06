class EuerExpensePoliciesController < ApplicationController
  def edit
    load_context
  end

  def update
    @year = selected_year
    workspace = workspace!
    saved = workspace.with_lock do
      @policy = workspace.euer_expense_policies.find_or_initialize_by(year: @year)
      @policy.update(params.require(:euer_expense_policy).permit(:deduction_method, :eligibility_confirmed, :home_office_method, :home_days, :home_months, :home_basis, :home_eligibility_confirmed, :daycare_eligibility_confirmed,
        daycare_rows: EuerDaycareAllowance::KEYS))
    end
    if saved
      redirect_to prepare_euer_bookkeeping_entries_path(year: @year), notice: "Ausgabenmethode gespeichert. Die EÜR wurde neu berechnet."
    else
      load_report
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def selected_year
    year = params[:year].present? ? params[:year].to_i : Date.current.year
    raise ActiveRecord::RecordNotFound unless EuerProfessionAllowance::RULES.key?(year)

    year
  end

  def load_context
    @year = selected_year
    @policy = current_workspace&.euer_expense_policies&.find_by(year: @year) || EuerExpensePolicy.new(year: @year)
    load_report
  end

  def load_report
    @report = BookkeepingReport.new(current_workspace ? current_workspace.bookkeeping_entries : BookkeepingEntry.none, @year,
      assets: current_workspace ? current_workspace.business_assets : BusinessAsset.none,
      adjustments: current_workspace ? current_workspace.euer_adjustments : EuerAdjustment.none,
      imports: current_workspace ? current_workspace.bookkeeping_imports : BookkeepingImport.none,
      statement: current_workspace&.euer_statements&.find_by(year: @year))
  end
end
