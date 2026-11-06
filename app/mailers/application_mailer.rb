class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAIL_FROM", "Kleinunternehmerzentrale <service@kleinunternehmerzentrale.de>") }
  layout "mailer"
end
