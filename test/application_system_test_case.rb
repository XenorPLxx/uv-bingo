require "test_helper"
require "selenium-webdriver"
Selenium::WebDriver.logger.level = :warn

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1440, 1100 ] do |options|
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
  end

  def browser_sign_in(participant)
    raw = LoginToken.issue!(participant: participant, interaction_id: SecureRandom.uuid)
    visit "/login?token=#{raw}"
    click_button "Zaloguj się"
    assert_selector ".user-name", text: participant.display_name, visible: :all
  end

  def mobile_viewport(width: 390, height: 844)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 2, mobile: true)
    assert_equal [ width, height ], page.evaluate_script("[window.innerWidth, window.innerHeight]"), "The browser must use the requested phone viewport"
  end

  def desktop_viewport(width: 1440, height: 1100)
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.current_window.resize_to(width, height)
  end
end
