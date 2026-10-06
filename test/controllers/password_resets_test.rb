require "test_helper"

class PasswordResetsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @workspace = Workspace.create!(email: "nutzer@example.de", password: "altes-passwort-1")
  end

  test "Mail wird nur für bestehende Konten verschickt, die Antwort ist immer gleich" do
    assert_enqueued_emails 1 do
      post password_resets_url, params: { email: "Nutzer@Example.de" }
    end
    assert_redirected_to new_session_url
    first = flash[:notice]

    assert_no_enqueued_emails do
      post password_resets_url, params: { email: "unbekannt@example.de" }
    end
    assert_equal first, flash[:notice]
  end

  test "Mail enthält einen Link, der ein neues Passwort erlaubt, und der Link gilt nur einmal" do
    perform_enqueued_jobs { post password_resets_url, params: { email: "nutzer@example.de" } }
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "nutzer@example.de" ], mail.to
    url = mail.text_part.body.to_s[%r{https?://\S+/password_resets/\S+/edit}]
    assert url

    get url
    assert_response :success

    old_token = @workspace.token
    patch url.sub("/edit", ""), params: { password: "neues-passwort-2", password_confirmation: "neues-passwort-2" }
    assert_redirected_to invoices_url
    @workspace.reload
    assert @workspace.authenticate("neues-passwort-2")
    assert_not_equal old_token, @workspace.token

    get url
    assert_redirected_to new_password_reset_url
  end

  test "zu kurzes Passwort wird abgelehnt" do
    token = @workspace.generate_token_for(:password_reset)
    patch password_reset_url(token), params: { password: "kurz", password_confirmation: "kurz" }
    assert_response :unprocessable_entity
    assert @workspace.reload.authenticate("altes-passwort-1")
  end

  test "abgelaufener oder falscher Link" do
    token = @workspace.generate_token_for(:password_reset)
    travel 31.minutes do
      get edit_password_reset_url(token)
      assert_redirected_to new_password_reset_url
    end
    get edit_password_reset_url("falsch")
    assert_redirected_to new_password_reset_url
  end
end
