class AccountsController < ApplicationController
  def new
    redirect_to invoices_path if current_workspace&.account?
  end

  # Aus dem Gast-Bereich wird ein Konto. Alle bisherigen Daten bleiben erhalten.
  def create
    workspace = workspace!
    if workspace.register(email: params[:email], password: params[:password], password_confirmation: params[:password_confirmation])
      redirect_to invoices_path, notice: "Dein Konto ist angelegt. Deine bisherigen Rechnungen und Angaben sind jetzt dauerhaft gespeichert."
    else
      @workspace = workspace
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    current_workspace&.erase!
    end_workspace
    redirect_to root_path, notice: "Alle deine Daten wurden gelöscht."
  end
end
