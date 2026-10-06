class SessionsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Zu viele Versuche. Bitte warte kurz." }

  def new
  end

  def create
    workspace = Workspace.find_by(email: Workspace.normalize_value_for(:email, params[:email].to_s))
    if workspace&.authenticate(params[:password].to_s)
      start_workspace(workspace)
      redirect_to invoices_path, notice: "Willkommen zurück."
    else
      flash.now[:alert] = "E-Mail-Adresse oder Passwort stimmt nicht."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    end_workspace
    redirect_to root_path, notice: "Du bist abgemeldet."
  end
end
