require "application_system_test_case"

class MobileNavigationTest < ApplicationSystemTestCase
  setup do
    @event = create_event(title: "TGA 2026 — próba głosowania")
    @admin = create_participant(display_name: "Administrator")
    @previous_admins = ENV["ADMIN_DISCORD_IDS"]
    ENV["ADMIN_DISCORD_IDS"] = @admin.discord_id
    desktop_viewport
    browser_sign_in(@admin)
    visit event_path(@event)
    Selenium::WebDriver::Wait.new(timeout: 5).until do
      page.evaluate_script("Boolean(window.Stimulus?.getControllerForElementAndIdentifier(document.querySelector('.mobile-navigation'), 'mobile-menu'))")
    end
  end

  teardown do
    ENV["ADMIN_DISCORD_IDS"] = @previous_admins
    desktop_viewport
  end

  test "phone menu dismisses on outside click and Escape while keeping navigation usable" do
    [ 320, 390 ].each do |width|
      mobile_viewport(width: width)
      assert_equal false, page.evaluate_script("document.documentElement.scrollWidth > innerWidth")
      find(".mobile-navigation > summary").click
      assert_selector ".mobile-navigation[open]"
      assert_selector 'nav[aria-label="Nawigacja główna"]', count: 1
      find(".mobile-navigation .user-name").click
      assert_selector ".mobile-navigation[open]"
      find(".hero h1").click
      assert_no_selector ".mobile-navigation[open]"

      find(".mobile-navigation > summary").click
      find('.mobile-navigation a[href="/admin"]').send_keys(:escape)
      assert_no_selector ".mobile-navigation[open]"
      assert_equal true, page.evaluate_script("document.activeElement === document.querySelector('.mobile-navigation > summary')")

      find(".mobile-navigation > summary").click
      find_field("Szukaj propozycji").click
      assert_no_selector ".mobile-navigation[open]"
      assert_equal "q", page.evaluate_script("document.activeElement.id"), "An outside click should focus its own target"
    end

    find(".mobile-navigation > summary").click
    within(".mobile-navigation") { click_link "Administracja" }
    assert_current_path admin_root_path
    find(".mobile-navigation > summary").click
    within(".mobile-navigation") { click_button "Wyloguj" }
    assert_current_path root_path
    assert_text "Wylogowano."
    assert_no_selector ".mobile-navigation[open]"
  end

  test "phone emulation clears when returning to the desktop breakpoint" do
    mobile_viewport(width: 760)
    assert_selector ".mobile-navigation"
    assert_no_selector ".desktop-navigation"

    desktop_viewport(width: 761)
    assert_equal 761, page.evaluate_script("window.innerWidth")
    assert_no_selector ".mobile-navigation"
    assert_selector ".desktop-navigation"
    assert_selector 'nav[aria-label="Nawigacja główna"]', count: 1

    mobile_viewport(width: 390)
    assert_selector ".mobile-navigation"
    assert_no_selector ".desktop-navigation"
  end
end
