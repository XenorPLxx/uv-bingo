require "application_system_test_case"

class SearchTest < ApplicationSystemTestCase
  setup do
    @event = create_event
    @voter = create_participant
    author = create_participant
    @witcher = @event.options.create!(participant: author, text: "Nowy zwiastun Wiedźmina IV")
    @announcement = @event.options.create!(participant: author, text: "Zapowiedź gry na scenie")
    @gabe = @event.options.create!(participant: author, text: "Gabe Newell pojawia się na scenie")
    15.times { |i| @event.options.create!(participant: author, text: "Pozostała propozycja #{i}") }
    Capybara.default_max_wait_time = 10
    page.current_window.resize_to(1440, 900)
    browser_sign_in(@voter)
    visit event_path(@event)
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    page.execute_script("window.searchDocument = 'original'")
  end

  test "typing debounces search and preserves focus viewport draft and filtered voting" do
    fill_in "Twoja propozycja", with: "Niedokończony pomysł"
    page.execute_script(<<~JS)
      window.searchOriginalFetch = window.fetch.bind(window);
      window.searchRequests = [];
      window.fetch = (input, options) => {
        const url = new URL(input, location.origin);
        if (url.pathname.endsWith('/state') && url.searchParams.has('refresh')) window.searchRequests.push(url.searchParams.get('q'));
        return window.searchOriginalFetch(input, options);
      };
      document.querySelector('.search-form').scrollIntoView({block:'start', behavior:'instant'});
      document.querySelector('.voting-sidebar').scrollTop = 100;
    JS
    before = search_viewport
    requests = page.evaluate_script(<<~JS)
      (() => {
        const input = document.querySelector('input[type=search]');
        input.focus({preventScroll:true});
        for (const query of ['w', 'wi', 'wiedź']) {
          input.value = query;
          input.dispatchEvent(new Event('input', {bubbles:true}));
        }
        input.setSelectionRange(2,2);
        return window.searchRequests.length;
      })()
    JS
    assert_equal 0, requests, "Typing should wait for the debounce"
    assert_selector ".option-card", count: 2
    assert_selector "#option-#{@witcher.id}"
    assert_selector "#option-#{@announcement.id}"
    assert_equal [ "wiedź" ], page.evaluate_script("window.searchRequests")
    assert_equal "q", page.evaluate_script("document.activeElement.id")
    assert_equal 2, page.evaluate_script("document.activeElement.selectionStart")
    assert_voting_search_viewport before
    assert_field "Twoja propozycja", with: "Niedokończony pomysł"
    assert_current_path event_path(@event, q: "wiedź")
    assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('input[type=search]')).outlineStyle")
    assert_not_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('.search-form')).boxShadow")
    save_screenshot(Rails.root.join("tmp/screenshots/search-desktop.png"))

    within("#option-#{@witcher.id}") { click_button "Głosuję +1" }
    assert_selector "#option-#{@witcher.id}.selected"
    assert_selector ".option-card", count: 2
    find("#ballot-#{@witcher.id}-remove").click
    assert_selector ".voting-feedback", text: "Głos cofnięty"
    assert_selector ".option-card", count: 2
    assert_no_selector "#option-#{@witcher.id}.selected"
    assert_current_path event_path(@event, q: "wiedź")

    fill_in "Szukaj propozycji", with: "Nieistniejący wynik"
    assert_selector ".empty-card", text: "Brak wyników."
    assert_no_selector ".option-card"
    page.execute_script("const input = document.querySelector('input[type=search]'); input.value=''; input.dispatchEvent(new Event('search',{bubbles:true}))")
    assert_selector ".option-card", count: 18
    assert_current_path event_path(@event)
    fill_in "Szukaj propozycji", with: "Gabe"
    find_field("Szukaj propozycji").send_keys(:enter)
    assert_selector ".option-card", count: 1
    assert_selector "#option-#{@gabe.id}"
    assert_equal "original", page.evaluate_script("window.searchDocument")

    page.current_window.resize_to(390, 844)
    fill_in "Szukaj propozycji", with: "wiedź"
    assert_selector ".option-card", count: 2
    assert_equal "q", page.evaluate_script("document.activeElement.id")
    assert_equal false, page.evaluate_script("document.documentElement.scrollWidth > innerWidth")
    save_screenshot(Rails.root.join("tmp/screenshots/search-mobile.png"))
  ensure
    page.execute_script("if(window.searchOriginalFetch) window.fetch=window.searchOriginalFetch")
  end

  test "old responses errors and a query changed while voting cannot replace newer search results" do
    page.execute_script(<<~JS)
      window.searchOriginalFetch = window.fetch.bind(window);
      window.searchRequests = [];
      window.fetch = async (input, options={}) => {
        const url = new URL(input, location.origin);
        if (!url.pathname.endsWith('/state')) return window.searchOriginalFetch(input, options);
        const query = url.searchParams.get('q');
        window.searchRequests.push(query);
        if (query === 'awaria') throw new TypeError('Simulated network failure');
        // Deliberately ignore abort to prove late responses are still rejected.
        const response = await window.searchOriginalFetch(input, {...options, signal:undefined});
        if (query === 'wiedź' && !window.delayedSearchFinished) {
          await new Promise(resolve => setTimeout(resolve,1000));
          window.delayedSearchFinished = true;
        }
        if (window.holdVotingRefresh && query === 'gabe') await new Promise(resolve => window.releaseVotingRefresh=resolve);
        return response;
      };
    JS
    fill_in "Szukaj propozycji", with: "wiedź"
    wait_for_search_script("window.searchRequests.includes('wiedź')")
    fill_in "Szukaj propozycji", with: "gabe"
    click_button "Szukaj"
    assert_selector ".option-card", count: 1
    assert_selector "#option-#{@gabe.id}"
    wait_for_search_script("window.delayedSearchFinished === true")
    assert_selector ".option-card", count: 1
    assert_selector "#option-#{@gabe.id}"
    assert_current_path event_path(@event, q: "gabe")

    fill_in "Szukaj propozycji", with: "awaria"
    assert_selector ".voting-feedback .alert", text: "Nie udało się odświeżyć wyników"
    assert_selector "#option-#{@gabe.id}"
    fill_in "Szukaj propozycji", with: "gabe"
    assert_no_selector ".voting-feedback .alert"
    assert_selector "#option-#{@gabe.id}"

    page.execute_script("window.holdVotingRefresh=true")
    within("#option-#{@gabe.id}") { click_button "Głosuję +1" }
    wait_for_search_script("typeof window.releaseVotingRefresh === 'function'")
    fill_in "Szukaj propozycji", with: "wiedź"
    page.execute_script("window.holdVotingRefresh=false; window.releaseVotingRefresh()")
    assert_selector ".option-card", count: 2
    assert_selector "#option-#{@witcher.id}"
    assert_selector "#option-#{@announcement.id}"
    assert_selector ".voting-feedback", text: "Głos zapisany. Pozostało: 4 z 5."
    assert_selector ".ballot-count", text: "1/5"
    assert_equal @gabe.id, @voter.votes.sole.option_id
    assert_current_path event_path(@event, q: "wiedź")
    assert_equal "original", page.evaluate_script("window.searchDocument")
  ensure
    page.execute_script("window.releaseVotingRefresh?.(); if(window.searchOriginalFetch) window.fetch=window.searchOriginalFetch")
  end

  private

  def search_viewport
    page.evaluate_script("({top:document.querySelector('.search-form').getBoundingClientRect().top,sidebar:document.querySelector('.voting-sidebar').scrollTop})")
  end

  def assert_voting_search_viewport(before)
    after = search_viewport
    assert_in_delta before.fetch("top"), after.fetch("top"), 2
    assert_in_delta before.fetch("sidebar"), after.fetch("sidebar"), 2
  end

  def wait_for_search_script(script)
    Selenium::WebDriver::Wait.new(timeout: 5).until { page.evaluate_script(script) }
  end
end
