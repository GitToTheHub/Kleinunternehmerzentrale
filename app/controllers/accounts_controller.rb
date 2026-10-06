class AccountsController < ApplicationController
  def new
    redirect_to invoices_path if current_workspace&.account?
  end

  # Aus dem Gast-Bereich wird ein Konto. Alle bisherigen Daten bleiben erhalten.
  def create
    workspace = workspace!
    if workspace.register(email: params[:email], password: params[:password], password_confirmation: params[:password_confirmation])
      ConfirmationMailer.confirm(workspace).deliver_later
      redirect_to invoices_path, notice: "Dein Konto ist angelegt. Wir haben dir eine E-Mail geschickt. Bitte klicke auf den Link darin, damit deine Daten dauerhaft gespeichert bleiben."
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
