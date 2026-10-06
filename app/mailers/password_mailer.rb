class PasswordMailer < ApplicationMailer
  def reset(workspace)
    @url = edit_password_reset_url(token: workspace.generate_token_for(:password_reset))
    mail to: workspace.email, subject: "Passwort zurücksetzen – Kleinunternehmerzentrale"
  end
end
