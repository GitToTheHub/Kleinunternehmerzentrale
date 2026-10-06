class PasswordResetsController < ApplicationController
  rate_limit to: 5, within: 10.minutes, only: :create, with: -> { redirect_to new_password_reset_path, alert: "Zu viele Versuche. Bitte warte kurz." }
  before_action :set_workspace, only: %i[edit update]

  def new
  end

  # Die Antwort ist immer gleich, damit niemand herausfinden kann, wer ein Konto hat.
  def create
    workspace = Workspace.find_by(email: Workspace.normalize_value_for(:email, params[:email].to_s))
    PasswordMailer.reset(workspace).deliver_later if workspace
    redirect_to new_session_path, notice: "Wenn es zu dieser Adresse ein Konto gibt, haben wir dir eine E-Mail mit einem Link geschickt. Er gilt 30 Minuten."
  end

  def edit
  end

  def update
    if @workspace.reset_password(password: params[:password], password_confirmation: params[:password_confirmation])
      start_workspace(@workspace)
      redirect_to invoices_path, notice: "Dein neues Passwort gilt. Auf anderen Geräten wurdest du abgemeldet."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_workspace
    @workspace = Workspace.find_by_token_for(:password_reset, params[:token])
    redirect_to new_password_reset_path, alert: "Der Link ist abgelaufen oder wurde schon benutzt. Fordere einen neuen an." unless @workspace
  end
end
