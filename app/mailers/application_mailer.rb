class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAIL_FROM", "Kleinunternehmerzentrale <noreply@example.com>") }
  layout "mailer"
end
