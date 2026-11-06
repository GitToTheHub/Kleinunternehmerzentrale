require "application_system_test_case"

class SiteNavigationTest < ApplicationSystemTestCase
  test "Desktopnavigation bleibt ausgerichtet und Rechnungen stehen vor Angeboten" do
    workspace = Workspace.create!(email: "navigation@example.test", password: "Navigation12345!", email_confirmed_at: Time.current)
    visit new_session_path
    fill_in "E-Mail-Adresse", with: workspace.email
    fill_in "Passwort", with: "Navigation12345!"
    click_button "Anmelden"
    assert_current_path invoices_path
    [ 1440, 1280, 1156, 1024 ].each do |width|
      viewport(width)
      visit root_path
      assert_no_selector ".site-nav-toggle", visible: true
      links = all(".site-nav a").map(&:text)
      assert_operator links.index("Rechnungen"), :<, links.index("Angebote & Aufträge")
      centers = page.evaluate_script("Array.from(document.querySelectorAll('.site-nav > a, .site-nav__button')).map(node => { const rect = node.getBoundingClientRect(); return rect.top + rect.height / 2; })")
      assert_operator centers.max - centers.min, :<=, 1
      assert_no_overflow
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/navigation-desktop.png"))
  end

  test "Smartphonemenue laesst sich oeffnen schliessen und mit Tastatur bedienen" do
    [ 320, 390, 760 ].each do |width|
      viewport(width)
      visit root_path
      assert_no_selector ".site-nav", visible: true
      assert_selector ".site-nav-toggle[aria-label='Menü öffnen']"
      find(".site-nav-toggle").click
      assert_selector ".site-nav", visible: true
      assert_selector "button[aria-expanded=true][aria-controls=site-navigation]"
      assert_no_overflow
      find(".site-nav a", text: "Angebote & Aufträge").send_keys(:escape)
      assert_no_selector ".site-nav", visible: true
      assert_selector ".site-nav-toggle:focus"
      find(".site-nav-toggle[aria-label='Menü öffnen']").click
      find("main h1").click
      assert_no_selector ".site-nav", visible: true
      find(".site-nav-toggle[aria-label='Menü öffnen']").click
      click_link "Angebote & Aufträge"
      assert_current_path sales_documents_path
      assert_no_selector ".site-nav", visible: true
    end
    viewport(390)
    find(".site-nav-toggle[aria-label='Menü öffnen']").click
    page.save_screenshot(Rails.root.join("tmp/screenshots/navigation-mobile.png"))
  end

  private

  def viewport(width)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: 900, deviceScaleFactor: 1, mobile: width <= 760)
  end

  def assert_no_overflow
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
