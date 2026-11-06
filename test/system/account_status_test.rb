require "application_system_test_case"

class AccountStatusTest < ApplicationSystemTestCase
  test "angemeldetes Konto zeigt die E-Mail auch auf schmalen Smartphones" do
    email = "eine-lange-kontoadresse-fuer-den-mobiltest@example.de"
    Workspace.create!(email: email, password: "geheimes-passwort", email_confirmed_at: Time.current)
    visit new_session_path
    assert_no_selector ".site-account"
    fill_in "E-Mail-Adresse", with: email
    fill_in "Passwort", with: "geheimes-passwort"
    click_button "Anmelden"
    assert_current_path invoices_path
    [ 320, 414, 1400 ].each do |width|
      page.driver.browser.manage.window.resize_to(width, 844)
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: 844, deviceScaleFactor: 1, mobile: width < 760)
      assert_selector "header .site-account", text: "Angemeldet als #{email}"
      assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    end
    click_button "Abmelden"
    assert_no_selector ".site-account"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.current_window.resize_to(1400, 1100)
  end
end
