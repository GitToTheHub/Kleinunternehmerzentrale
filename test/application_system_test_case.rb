require "test_helper"
require "selenium-webdriver"

Selenium::WebDriver.logger.level = :warn

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1100 ] do |options|
    options.add_option("goog:loggingPrefs", { browser: "ALL" })
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
