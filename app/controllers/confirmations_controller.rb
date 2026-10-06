class ConfirmationsController < ApplicationController
  rate_limit to: 3, within: 10.minutes, only: :create, with: -> { redirect_to invoices_path, alert: "Zu viele Versuche. Bitte warte kurz." }

  def show
    workspace = Workspace.find_by_token_for(:email_confirmation, params[:token])
    if workspace
      workspace.confirm_email!
      redirect_to(current_workspace == workspace ? invoices_path : new_session_path, notice: "Danke, deine E-Mail-Adresse ist bestätigt. Deine Daten bleiben dauerhaft gespeichert.")
    else
      redirect_to root_path, alert: "Der Link ist abgelaufen. Melde dich an und lass dir einen neuen schicken."
    end
  end

  def create
    workspace = current_workspace
    if workspace&.account? && !workspace.email_confirmed?
      ConfirmationMailer.confirm(workspace).deliver_later
      redirect_to invoices_path, notice: "Wir haben dir den Link noch einmal geschickt."
    else
      redirect_to invoices_path
    end
  end
end
