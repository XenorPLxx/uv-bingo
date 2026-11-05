require "application_system_test_case"

class BingoTest < ApplicationSystemTestCase
  setup do
    @event = create_event
    @voter = create_participant(display_name: "Tester UV")
    @previous_admins = ENV["ADMIN_DISCORD_IDS"]
    ActionCable.server.config.cable = { "adapter" => "async" }
    Capybara.default_max_wait_time = 10
    desktop_viewport
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
      fill_in "Twoja propozycja", with: "Zachowany szkic" if index == 3
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
    assert_field "Twoja propozycja", with: "Zachowany szkic"
    assert_selector "[data-option-preview-target=count]", text: "15/100"
    within("#option-#{own_option.id}") { click_button "Głosuję +1" }
    assert_text "Głos zapisany. Pozostało: 0 z 5."
    assert_equal 5, @voter.votes.count
    assert_no_text "Każdy głos ma tę samą wagę"
    save_screenshot(Rails.root.join("tmp/screenshots/voting-desktop.png"))
    mobile_viewport
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

  test "voting and background sorting preserve the visible list sidebar and draft" do
    options = seed_options(@event, 30)
    browser_sign_in(@voter)
    visit event_path(@event)
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    fill_in "Twoja propozycja", with: "Niedokończona propozycja"
    page.execute_script("window.votingDocument = 'original'; document.activeElement.blur()")
    page.execute_script("document.getElementById('option-#{options[16].id}').scrollIntoView({block: 'center', behavior: 'instant'}); document.querySelector('.voting-sidebar').scrollTop = 100")
    anchor = "#option-#{options[17].id}"
    before = voting_viewport(anchor)
    within("#option-#{options[16].id}") { click_button "Głosuję +1" }
    assert_selector ".voting-feedback", text: "Głos zapisany. Pozostało: 4 z 5."
    assert_selector "#option-#{options[16].id}.selected"
    assert_voting_viewport before, anchor
    assert_field "Twoja propozycja", with: "Niedokończona propozycja"
    assert_current_path event_path(@event)
    assert_equal "original", page.evaluate_script("window.votingDocument")
    assert_no_selector ".page-container > .flash"

    Voting.cast!(event: @event, participant: create_participant, option_id: options[25].id)
    page.execute_script("window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('.voting-shell'), 'event-status').refresh()")
    assert_selector "#option-#{options[25].id} .option-count", text: "2"
    assert_voting_viewport before, anchor
    assert_equal "original", page.evaluate_script("window.votingDocument")

    page.execute_script("document.getElementById('option-#{options[16].id}').scrollIntoView({block: 'center', behavior: 'instant'})")
    withdrawal_anchor = "#option-#{options[25].id}"
    before = voting_viewport(withdrawal_anchor)
    within("#option-#{options[16].id}") { click_button "Cofnij głos" }
    assert_selector ".voting-feedback", text: "Głos cofnięty. Propozycja zostaje. Pozostało: 5 z 5."
    assert_voting_viewport before, withdrawal_anchor
    assert_current_path event_path(@event)
    assert_field "Twoja propozycja", with: "Niedokończona propozycja"
    assert_equal "original", page.evaluate_script("window.votingDocument")
    save_screenshot(Rails.root.join("tmp/screenshots/voting-in-place.png"))
    mobile_viewport
    page.execute_script("document.getElementById('option-#{options[18].id}').scrollIntoView({block: 'center', behavior: 'instant'})")
    mobile_anchor = "#option-#{options[19].id}"
    before = voting_viewport(mobile_anchor)
    within("#option-#{options[18].id}") { click_button "Głosuję +1" }
    assert_selector ".voting-feedback", text: "Głos zapisany. Pozostało: 4 z 5."
    assert_selector "#option-#{options[18].id}.selected"
    assert_voting_viewport before, mobile_anchor
    assert_current_path event_path(@event)
    assert_equal "original", page.evaluate_script("window.votingDocument")
    assert_equal false, page.evaluate_script("document.documentElement.scrollWidth > window.innerWidth")
    save_screenshot(Rails.root.join("tmp/screenshots/voting-in-place-mobile.png"))
  end

  test "signed in participants open voter names from the vote count and the dialog follows refreshes" do
    watched, other, lonely = 3.times.map { |index| @event.options.create!(participant: @voter, text: "Propozycja #{index + 1}") }
    Voting.cast!(event: @event, participant: create_participant(display_name: "Fanka Wiedźmina"), option_id: watched.id)
    Voting.cast!(event: @event, participant: create_participant(display_name: "Kolega z czatu"), option_id: other.id)
    lonely_vote = Voting.cast!(event: @event, participant: create_participant(display_name: "Samotny Głos"), option_id: lonely.id)
    visit event_path(@event)
    assert_selector "#option-#{watched.id} span.option-count", text: "1"
    assert_no_selector "button.option-count"

    browser_sign_in(@voter)
    assert_no_text "Fanka Wiedźmina"
    find("#option-#{watched.id}-count").click
    within("dialog#voters-dialog[open]") do
      assert_selector "h2", text: watched.text
      assert_text "KTO GŁOSOWAŁ · 1"
      assert_selector "li", text: "Fanka Wiedźmina"
    end
    Voting.cast!(event: @event, participant: create_participant(display_name: "Nowy Widz"), option_id: watched.id)
    page.execute_script("window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('.voting-shell'), 'event-status').refresh()")
    within("dialog#voters-dialog[open]") do
      assert_text "KTO GŁOSOWAŁ · 2"
      assert_equal [ "Fanka Wiedźmina", "Nowy Widz" ], all("li").map(&:text)
    end
    save_screenshot(Rails.root.join("tmp/screenshots/voters-desktop.png"))
    find("#voters-dialog .dialog-close").click
    assert_no_selector "dialog[open]"
    assert_equal "option-#{watched.id}-count", page.evaluate_script("document.activeElement.id")

    within("#option-#{other.id}") { click_button "Głosuję +1" }
    assert_selector ".voting-feedback", text: "Głos zapisany."
    find("#option-#{other.id}-count").click
    assert_selector "dialog#voters-dialog[open] li", text: "Tester UV"
    find("#voters-dialog .dialog-close").send_keys(:escape)
    assert_no_selector "dialog[open]"

    find("#option-#{lonely.id}-count").click
    assert_selector "dialog#voters-dialog[open] li", text: "Samotny Głos"
    Voting.withdraw!(event: @event, participant: lonely_vote.participant, vote_id: lonely_vote.id)
    page.execute_script("window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('.voting-shell'), 'event-status').refresh()")
    assert_no_selector "dialog[open]"
    assert_selector "#option-#{lonely.id} span.option-count", text: "0"

    mobile_viewport
    find("#option-#{watched.id}-count").click
    assert_selector "dialog#voters-dialog[open] li", count: 2
    assert_equal false, page.evaluate_script("document.documentElement.scrollWidth > window.innerWidth")
    save_screenshot(Rails.root.join("tmp/screenshots/voters-mobile.png"))
    page.driver.browser.action.move_to_location(5, 5).click.perform
    assert_no_selector "dialog[open]"
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
    mobile_viewport
    assert_board_text_fits
    assert_equal false, page.evaluate_script("document.documentElement.scrollWidth > window.innerWidth")
    desktop_viewport(width: 1920, height: 1080)
    assert_board_text_fits
    save_screenshot(Rails.root.join("tmp/screenshots/presentation-admin.png"))
    Capybara.using_session(:viewer) do
      assert_selector ".mark-cross[data-position='0']", wait: 10
      desktop_viewport(width: 1920, height: 1080)
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

  test "saved draw reveal really restarts without changing its result and supports reduced motion" do
    seed_options(@event, 25)
    @event.update!(closes_at: 1.second.ago)
    draw = BoardDraw.call(event: @event, admin: @voter)
    record = draw.attributes
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "no-preference" } ])
    visit reveal_event_path(@event)
    page.execute_script("window.cspViolations = []; document.addEventListener('securitypolicyviolation', event => window.cspViolations.push(event.violatedDirective))")
    click_button "Odsłoń wylosowaną planszę ✦"
    assert_selector "[data-reveal-target=status]", text: "Odsłanianie planszy…"
    assert_equal 25, page.evaluate_script("document.querySelector('.reveal-grid').getAnimations({subtree:true}).length")
    assert_operator page.evaluate_script("parseFloat(getComputedStyle(document.querySelector('.bingo-cell:last-child')).opacity)"), :<, 0.1
    assert_selector "[data-reveal-target=status]", exact_text: "Plansza odsłonięta."
    click_button "Odtwórz ten sam wynik ponownie ↻"
    assert_selector "[data-reveal-target=status]", text: "Odsłanianie planszy…"
    assert_equal 25, page.evaluate_script("document.querySelector('.reveal-grid').getAnimations({subtree:true}).length")
    assert_operator page.evaluate_script("parseFloat(getComputedStyle(document.querySelector('.bingo-cell:last-child')).opacity)"), :<, 0.1
    click_button "Odtwórz ten sam wynik ponownie ↻"
    assert_equal 25, page.evaluate_script("document.querySelector('.reveal-grid').getAnimations({subtree:true}).length")
    assert_selector "[data-reveal-target=status]", exact_text: "Plansza odsłonięta."
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    click_button "Odtwórz ten sam wynik ponownie ↻"
    assert_selector "[data-reveal-target=status]", text: "Animacje są wyłączone"
    assert_equal 0, page.evaluate_script("document.querySelector('.reveal-grid').getAnimations({subtree:true}).length")
    assert_equal true, page.evaluate_script("Array.from(document.querySelectorAll('.bingo-cell')).every(cell => getComputedStyle(cell).opacity === '1')")
    assert_equal record, draw.reload.attributes
    assert_equal draw.result, @event.cells.order(:position).pluck(:option_id)
    assert_equal 1, @event.audit_entries.where(action: "draw").count
    page.execute_script("window.Turbo.config.drive.progressBarDelay = 0")
    click_link "Przejdź do planszy →"
    assert_selector ".bingo-cell", count: 25
    assert_equal true, page.evaluate_script("Array.from(document.querySelectorAll('style')).some(style => style.textContent.includes('.turbo-progress-bar') && style.nonce.length > 0)")
    assert_empty page.evaluate_script("window.cspViolations")
  end

  test "twentieth proposal hides submission but sidebar withdrawal and stale option feedback still work" do
    19.times { |i| @event.options.create!(participant: @voter, text: "Moja wcześniejsza propozycja #{i}") }
    other, stale = seed_options(@event, 2)
    browser_sign_in(@voter)
    page.execute_script("window.votingDocument = 'original'")
    assert_selector ".authored-option-count", text: "19/20"
    fill_in "Twoja propozycja", with: "Moja dwudziesta propozycja"
    click_button "Dodaj propozycję +1"
    assert_selector ".voting-feedback", text: "Propozycja dodana"
    assert_selector ".authored-option-count", text: "20/20"
    assert_no_field "Twoja propozycja"
    within("#option-#{other.id}") { click_button "Głosuję +1" }
    assert_selector ".ballot-count", text: "2/5"
    own_option = @event.options.find_by!(text: "Moja dwudziesta propozycja")
    find("#ballot-#{own_option.id}-remove").click
    assert_selector ".voting-feedback", text: "Głos cofnięty"
    assert_selector ".ballot-count", text: "1/5"
    assert_selector ".authored-option-count", text: "20/20"
    assert_no_field "Twoja propozycja"
    assert Option.exists?(own_option.id)
    stale.update!(disqualified_at: Time.current)
    @event.increment!(:revision)
    within("#option-#{stale.id}") { click_button "Głosuję +1" }
    assert_selector ".voting-feedback .alert", text: "nie jest już dostępna"
    assert_no_selector "#option-#{stale.id}"
    assert_equal 1, @voter.votes.count
    assert_equal "original", page.evaluate_script("window.votingDocument")
  end

  private

  def voting_viewport(selector)
    page.evaluate_script("({top: document.querySelector('#{selector}').getBoundingClientRect().top, sidebar: document.querySelector('.voting-sidebar').scrollTop})")
  end

  def assert_voting_viewport(before, selector)
    after = voting_viewport(selector)
    assert_in_delta before.fetch("top"), after.fetch("top"), 2, "The visible proposals should not jump"
    assert_in_delta before.fetch("sidebar"), after.fetch("sidebar"), 2, "Sidebar scroll should be retained"
  end

  def assert_board_text_fits
    fits = Selenium::WebDriver::Wait.new(timeout: 5).until do
      page.evaluate_script("Array.from(document.querySelectorAll('.cell-text span')).every(text => text.offsetHeight <= text.parentElement.clientHeight - 8)")
    end
    assert fits, "Full option text must fit without overlapping board controls"
  end
end
