require "test_helper"
require "selenium-webdriver"

Selenium::WebDriver.logger.level = :warn

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  selenium_options = {}
  if ENV["SELENIUM_REMOTE_URL"].present?
    selenium_options[:browser] = :remote
    selenium_options[:url] = ENV.fetch("SELENIUM_REMOTE_URL")
    Capybara.server_host = "0.0.0.0"
    Capybara.server_port = 31339
    Capybara.app_host = "http://host.docker.internal:31339"
  end

  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1100 ], options: selenium_options do |options|
    options.add_option("goog:loggingPrefs", { browser: "ALL" })
    if ENV["SELENIUM_REMOTE_URL"].present?
      options.add_argument("--no-sandbox")
      options.add_argument("--disable-dev-shm-usage")
    end
  end

  setup do
    if ENV["SELENIUM_REMOTE_URL"].present?
      # Remote WebDriver must not treat text matching a local directory (e.g. TEST) as a file upload.
      page.driver.browser.file_detector = ->((filename, *)) { filename if File.file?(filename) }
    end
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    page.current_window.resize_to(1400, 1100)
  end

  def expense_position(key, _year = nil)
    EuerFields.selection_label(key)
  end

  def select_expense(key)
    click_button "Ausgabenbereich ändern" if page.has_button?("Ausgabenbereich ändern", wait: 0)
    within "#expense-area-cards" do
      find("input[type=radio][value='#{ApplicationController.helpers.bookkeeping_expense_group(key)}']").find(:xpath, "ancestor::label").click
    end
    click_button "Ausgabenart ändern" if page.has_button?("Ausgabenart ändern", wait: 0) && page.has_no_selector?("#expense-type-cards input:enabled", wait: 0)
    within "#expense-type-cards" do
      find("input[type=radio][value='#{key}']").find(:xpath, "ancestor::label").click
    end
  end

  Capybara.automatic_label_click = true
  Capybara.default_max_wait_time = 8
end
