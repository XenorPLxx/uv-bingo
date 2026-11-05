require "application_system_test_case"

class BingoTest < ApplicationSystemTestCase
  setup do
    @event = create_event
    @voter = create_participant(display_name: "Tester UV")
    @previous_admins = ENV["ADMIN_DISCORD_IDS"]
    ActionCable.server.config.cable = { "adapter" => "async" }
    Capybara.default_max_wait_time = 10
  end

  teardown do
    ENV["ADMIN_DISCORD_IDS"] = @previous_admins
  end

  test "participant can add an option and fill all five final votes" do
    seed_options(@event, 6)
    browser_sign_in(@voter)
    fill_in "Twoja propozycja", with: "Nowe przygody naszej ekipy"
    accept_confirm { click_button "Dodaj propozycję +1" }
    assert_text "Propozycja dodana z Twoim głosem"
    4.times do |index|
      accept_confirm { first(:button, "Głosuję +1").click }
      assert_text "Głos zapisany. Pozostało: #{3 - index} z 5."
    end
    assert_text "Twoje pięć głosów już jest w grze"
    assert_no_button "Głosuję +1"
    assert_equal 5, @voter.votes.count
    save_screenshot(Rails.root.join("tmp/screenshots/voting-desktop.png"))
    page.current_window.resize_to(390, 844)
    assert_selector "h1", text: "Wielkie zapowiedzi"
    assert_equal false, page.evaluate_script("document.documentElement.scrollWidth > window.innerWidth")
    save_screenshot(Rails.root.join("tmp/screenshots/voting-mobile.png"))
  end

  test "admin marks update a second browser and presentation is free of controls" do
    ENV["ADMIN_DISCORD_IDS"] = @voter.discord_id
    seed_options(@event, 25).each_with_index do |option, index|
      option.update!(text: DemoEvent::IDEAS.fetch(index))
    end
    @event.options.first.update!(text: "Bardzo długa zapowiedź nowej gry z rozbudowanym zwiastunem, wieloma bohaterami i premierą w przyszłości".first(100))
    @event.update!(closes_at: 1.second.ago)
    BoardDraw.call(event: @event, admin: @voter)
    @event.update!(state: "live")
    browser_sign_in(@voter)
    Capybara.using_session(:viewer) do
      visit presentation_event_path(@event)
      assert_selector ".bingo-cell", count: 25
      assert_no_selector ".cell-open"
      assert_text "POŁĄCZONO NA ŻYWO"
    end
    find("button[aria-label='Oznacz pole 1']").click
    within "dialog[open] .admin-mark-section" do
      accept_confirm { click_button "X", exact: true }
    end
    assert_text "Oznaczenie zapisane"
    Capybara.using_session(:viewer) do
      assert_selector ".mark-cross[data-position='0']", wait: 10
      page.current_window.resize_to(1920, 1080)
      fits = Selenium::WebDriver::Wait.new(timeout: 5).until do
        page.evaluate_script("Array.from(document.querySelectorAll('.cell-text span')).every(text => text.offsetHeight <= text.parentElement.clientHeight - 8)")
      end
      assert fits, "Full option text must fit without overlapping proposal counts"
      save_screenshot(Rails.root.join("tmp/screenshots/presentation.png"))
    end
  end
end
