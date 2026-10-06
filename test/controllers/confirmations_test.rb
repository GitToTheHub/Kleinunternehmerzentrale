require "test_helper"

class ConfirmationsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "Konto anlegen verschickt Bestätigungsmail, der Link bestätigt" do
    get new_account_url
    assert_enqueued_emails 1 do
      post account_url, params: { email: "neu@example.de", password: "ein-langes-passwort", password_confirmation: "ein-langes-passwort" }
    end
    workspace = Workspace.find_by!(email: "neu@example.de")
    assert_not workspace.email_confirmed?

    follow_redirect!
    assert_select ".guest-notice", /bestätige deine E-Mail/

    get confirm_email_url(token: workspace.generate_token_for(:email_confirmation))
    assert_redirected_to invoices_url
    assert workspace.reload.email_confirmed?
    follow_redirect!
    assert_select ".guest-notice", false
  end

  test "Link erneut senden und ungültiger Link" do
    post account_url, params: { email: "neu@example.de", password: "ein-langes-passwort", password_confirmation: "ein-langes-passwort" }
    assert_enqueued_emails 1 do
      post confirmation_url
    end
    get confirm_email_url(token: "falsch")
    assert_redirected_to root_url
    assert_not Workspace.find_by!(email: "neu@example.de").email_confirmed?
  end

  test "unbestätigte Konten werden wie Gäste gelöscht, bestätigte nicht" do
    old = 4.months.ago
    unconfirmed = Workspace.create!(email: "a@example.de", password: "ein-langes-passwort", last_active_at: old)
    confirmed = Workspace.create!(email: "b@example.de", password: "ein-langes-passwort", last_active_at: old, email_confirmed_at: old)
    Workspace.purge_expired_guests
    assert_not Workspace.exists?(unconfirmed.id)
    assert Workspace.exists?(confirmed.id)
  end

  test "Passwort-Reset bestätigt die Adresse" do
    workspace = Workspace.create!(email: "a@example.de", password: "ein-langes-passwort")
    patch password_reset_url(workspace.generate_token_for(:password_reset)), params: { password: "neues-passwort-2", password_confirmation: "neues-passwort-2" }
    assert workspace.reload.email_confirmed?
  end
end
