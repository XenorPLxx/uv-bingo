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
    click_button "Wchodzę do gry →"
    assert_text "Jesteś w grze"
  end
end
