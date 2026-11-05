require "application_system_test_case"

class BingoTest < ApplicationSystemTestCase
  setup do
    @event = create_event
    @voter = create_participant(display_name: "Tester UV")
    @previous_admins = ENV["ADMIN_DISCORD_IDS"]
    ActionCable.server.config.cable = { "adapter" => "async" }
    Capybara.default_max_wait_time = 10
    page.current_window.resize_to(1440, 1100)
  end

  teardown do
    ENV["ADMIN_DISCORD_IDS"] = @previous_admins
  end

  test "participant can replace a vote at the five vote limit while keeping their option" do
    options = seed_options(@event, 6)
    browser_sign_in(@voter)
    fill_in "Twoja propozycja", with: "Nowe przygody naszej ekipy"
    click_button "Dodaj propozycję +1"
    assert_text "Propozycja dodana z Twoim głosem"
    options.first(4).each_with_index do |option, index|
      within("#option-#{option.id}") { click_button "Głosuję +1" }
      assert_text "Głos zapisany. Pozostało: #{3 - index} z 5."
      assert_selector "#option-#{option.id}.selected"
    end
    assert_text "Wykorzystano 5 głosów"
    assert_no_button "Głosuję +1"
    assert_equal 5, @voter.votes.count
    own_option = @event.options.find_by!(text: "Nowe przygody naszej ekipy")
    within("#option-#{own_option.id}") { click_button "Cofnij głos" }
    assert_text "Głos cofnięty. Propozycja zostaje. Pozostało: 1 z 5."
    assert_text own_option.text
    assert_equal 0, own_option.votes.count
    assert_selector ".ballot-count", text: "4/5"
    within("#option-#{own_option.id}") { click_button "Głosuję +1" }
    assert_text "Głos zapisany. Pozostało: 0 z 5."
    assert_equal 5, @voter.votes.count
    assert_no_text "Każdy głos ma tę samą wagę"
    save_screenshot(Rails.root.join("tmp/screenshots/voting-desktop.png"))
    page.current_window.resize_to(390, 844)
    assert_selector "h1", text: @event.title
    assert_equal false, page.evaluate_script("document.documentElement.scrollWidth > window.innerWidth")
    save_screenshot(Rails.root.join("tmp/screenshots/voting-mobile.png"))
  end

  test "admin merges duplicates and an open voting page updates the refunded allowance" do
    ENV["ADMIN_DISCORD_IDS"] = @voter.discord_id
    source, target = seed_options(@event, 6).first(2)
    Voting.cast!(event: @event, participant: @voter, option_id: source.id)
    Voting.cast!(event: @event, participant: @voter, option_id: target.id)
    browser_sign_in(@voter)
    Capybara.using_session(:voter_before_merge) do
      browser_sign_in(@voter)
      assert_selector ".ballot-count", text: "2/5"
    end
    visit admin_event_path(@event)
    find(".merge-panel > summary").click
    select "#{source.text} · głosy: 2", from: "Propozycja do połączenia"
    select "#{target.text} · głosy: 2", from: "Propozycja, która pozostanie"
    fill_in "Powód połączenia", with: "Dwie wersje tego samego pomysłu"
    accept_confirm { click_button "Połącz propozycje" }
    assert_text "Przeniesione głosy: 1. Zwrócone głosy: 1."
    assert_selector "#moderation-option-#{source.id} .merge-destination", text: target.text
    assert_no_selector "#moderation-option-#{source.id} .moderation-form"
    find(".merge-panel > summary").click
    save_screenshot(Rails.root.join("tmp/screenshots/admin-merge.png"))
    Capybara.using_session(:voter_before_merge) do
      assert_selector ".ballot-count", text: "1/5", wait: 20
      assert_no_selector "#option-#{source.id}"
      assert_selector "#option-#{target.id}.selected"
      first(:button, "Głosuję +1").click
      assert_text "Głos zapisany. Pozostało: 3 z 5."
    end
  end

  test "inline proposals and admin decisions update other viewers from both board views" do
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
      assert_no_selector ".proposal-button, .decision-button"
      assert_text "POŁĄCZONO NA ŻYWO"
    end
    find('button[aria-label="Zaproponuj ? w polu 1 (0)"]').click
    assert_selector '[data-position="0"] .question-count[aria-pressed="true"]'
    assert_no_selector "dialog"
    Capybara.using_session(:viewer) do
      within('[data-position="0"] .question-count') { assert_text "1" }
    end
    find('button[aria-label="Cofnij propozycję ? w polu 1 (1)"]').click
    assert_selector '[data-position="0"] .question-count[aria-pressed="false"]'
    visit presentation_event_path(@event)
    assert_selector ".proposal-button", count: 50
    assert_selector ".decision-button", count: 50
    find('button[aria-label="Ustaw oficjalne ? w polu 1"]').click
    assert_selector '.mark-question[data-position="0"]'
    assert_current_path presentation_event_path(@event)
    find('button[aria-label="Wyczyść oficjalne ? w polu 1"]').click
    assert_selector '.mark-blank[data-position="0"]'
    find('button[aria-label="Ustaw oficjalne X w polu 1"]').click
    assert_selector '.mark-cross[data-position="0"]'
    assert_text "Oznaczenie zapisane"
    assert_current_path presentation_event_path(@event)
    page.current_window.resize_to(390, 844)
    assert_board_text_fits
    assert_equal false, page.evaluate_script("document.documentElement.scrollWidth > window.innerWidth")
    page.current_window.resize_to(1920, 1080)
    assert_board_text_fits
    save_screenshot(Rails.root.join("tmp/screenshots/presentation-admin.png"))
    Capybara.using_session(:viewer) do
      assert_selector ".mark-cross[data-position='0']", wait: 10
      page.current_window.resize_to(1920, 1080)
      assert_board_text_fits
      save_screenshot(Rails.root.join("tmp/screenshots/presentation.png"))
    end
  end
  test "admin can review and delete a drawn event and live viewers leave the deleted board" do
    ENV["ADMIN_DISCORD_IDS"] = @voter.discord_id
    seed_options(@event, 25)
    @event.update!(closes_at: 1.second.ago)
    BoardDraw.call(event: @event, admin: @voter)
    @event.update!(state: "live")
    browser_sign_in(@voter)
    Capybara.using_session(:deleted_board_viewer) do
      visit presentation_event_path(@event)
      assert_selector ".bingo-cell", count: 25
      assert_text "POŁĄCZONO NA ŻYWO"
    end
    visit admin_event_path(@event)
    click_link "Usuń wydarzenie"
    assert_selector "h1", text: "Usuń wydarzenie"
    assert_text "Tej operacji nie można cofnąć."
    assert Event.exists?(@event.id)
    fill_in "confirmation", with: @event.slug
    click_button "Usuń trwale"
    assert_current_path admin_root_path
    assert_text "Wydarzenie zostało usunięte."
    assert_not Event.exists?(@event.id)
    Capybara.using_session(:deleted_board_viewer) do
      assert_current_path root_path(removed: "1"), wait: 15
      assert_text "Wydarzenie zostało usunięte."
      assert_no_selector ".bingo-cell"
    end
  end

  private

  def assert_board_text_fits
    fits = Selenium::WebDriver::Wait.new(timeout: 5).until do
      page.evaluate_script("Array.from(document.querySelectorAll('.cell-text span')).every(text => text.offsetHeight <= text.parentElement.clientHeight - 8)")
    end
    assert fits, "Full option text must fit without overlapping board controls"
  end
end
