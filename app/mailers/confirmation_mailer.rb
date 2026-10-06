class ConfirmationMailer < ApplicationMailer
  def confirm(workspace)
    @url = confirm_email_url(token: workspace.generate_token_for(:email_confirmation))
    mail to: workspace.email, subject: "Bitte bestätige deine E-Mail-Adresse – Kleinunternehmerzentrale"
  end
end
