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
    desktop_viewport(height: 900)
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

    mobile_viewport
    fill_in "Szukaj propozycji", with: "wiedź"
    assert_selector ".option-card", count: 2
    assert_equal "q", page.evaluate_script("document.activeElement.id")
    assert_equal false, page.evaluate_script("document.documentElement.scrollWidth > innerWidth")
    save_screenshot(Rails.root.join("tmp/screenshots/search-mobile.png"))
  ensure
    page.execute_script("if(window.searchOriginalFetch) window.fetch=window.searchOriginalFetch")
  end

  test "a search without results adds the searched text, clears the search and keeps the sidebar draft" do
    query = "  Nieistniejący   wynik  Ⅳ  "
    normalized_text = "Nieistniejący wynik IV"
    fill_in "Twoja propozycja", with: "Szkic w panelu"
    fill_in "Szukaj propozycji", with: query
    assert_selector ".empty-card h2", text: "Brak wyników."
    assert_no_selector ".empty-card p"
    assert_no_selector ".option-card"
    assert_no_text "Nowa propozycja otrzyma Twój głos"
    save_screenshot(Rails.root.join("tmp/screenshots/search-empty-desktop.png"))
    click_button "Dodaj „#{normalized_text}”"
    assert_selector ".voting-feedback", text: "Propozycja dodana z Twoim głosem. Pozostało: 4 z 5."
    added = @event.options.find_by!(text: normalized_text)
    assert_selector ".option-card", count: 19
    assert_selector "#option-#{added.id}.selected", text: normalized_text
    assert_no_selector ".empty-card"
    assert_field "Twoja propozycja", with: "Szkic w panelu"
    assert_field "Szukaj propozycji", with: ""
    assert_current_path event_path(@event)
    assert_equal "original", page.evaluate_script("window.searchDocument")

    mobile_viewport
    long_query = "Bardzo długa propozycja " * 4
    fill_in "Szukaj propozycji", with: long_query
    assert_selector "#search-option-submit", text: long_query.squish
    assert_equal false, page.evaluate_script("document.documentElement.scrollWidth > innerWidth")
    page.execute_script("document.querySelector('.empty-card').scrollIntoView({block: 'center', behavior: 'instant'})")
    save_screenshot(Rails.root.join("tmp/screenshots/search-empty-mobile.png"))
  end

  test "a new search typed while adding a proposal is not cleared by the save response" do
    fill_in "Twoja propozycja", with: "Zachowany szkic"
    fill_in "Szukaj propozycji", with: "Nowa propozycja z wyszukiwania"
    assert_selector "#search-option-submit"
    page.execute_script(<<~JS)
      window.searchOriginalFetch = window.fetch.bind(window);
      window.fetch = async (input, options = {}) => {
        const response = await window.searchOriginalFetch(input, options);
        if (options.method === 'POST' && new URL(input, location.origin).pathname.endsWith('/options')) {
          await new Promise(resolve => window.releaseProposal = resolve);
        }
        return response;
      };
    JS
    click_button "Dodaj „Nowa propozycja z wyszukiwania”"
    wait_for_search_script("typeof window.releaseProposal === 'function'")
    fill_in "Szukaj propozycji", with: "Gabe"
    page.execute_script("window.releaseProposal()")
    assert_selector ".voting-feedback", text: "Propozycja dodana"
    assert_field "Szukaj propozycji", with: "Gabe"
    assert_selector ".option-card", count: 1
    assert_selector "#option-#{@gabe.id}"
    assert_current_path event_path(@event, q: "Gabe")
    assert_field "Twoja propozycja", with: "Zachowany szkic"
    assert_equal "Nowa propozycja z wyszukiwania", @voter.votes.sole.option.text
  ensure
    page.execute_script("window.releaseProposal?.(); if(window.searchOriginalFetch) window.fetch=window.searchOriginalFetch")
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

  test "a timed out search reports failure and polling retries while search retains focus" do
    fill_in "Szukaj propozycji", with: "gabe"
    assert_selector "#option-#{@gabe.id}"
    page.execute_script(<<~JS)
      window.searchOriginalFetch = window.fetch.bind(window);
      window.hangSearch = true;
      window.fetch = (input, options={}) => {
        const url = new URL(input, location.origin);
        if (url.pathname.endsWith('/state') && url.searchParams.get('q') === 'wiedź' && window.hangSearch) {
          return new Promise((resolve,reject) => options.signal.addEventListener('abort', () => reject(new DOMException('Timed out', 'AbortError')), {once:true}));
        }
        return window.searchOriginalFetch(input, options);
      };
    JS
    fill_in "Szukaj propozycji", with: "wiedź"
    assert_selector ".voting-feedback .alert", text: "Nie udało się odświeżyć wyników", wait: 12
    assert_selector "[data-event-status-target=searchStatus]", text: "Nie udało się odświeżyć wyników.", visible: :all
    assert_selector "#option-#{@gabe.id}"
    assert_no_selector "[data-event-status-target=options][aria-busy=true]"
    assert_equal "q", page.evaluate_script("document.activeElement.id")
    page.execute_script("window.hangSearch=false")
    assert_selector ".option-card", count: 2, wait: 20
    assert_selector "#option-#{@witcher.id}"
    assert_selector "#option-#{@announcement.id}"
    assert_no_selector ".voting-feedback .alert"
    assert_selector "[data-event-status-target=searchStatus]", text: "Wyniki: 2.", visible: :all
    assert_equal "q", page.evaluate_script("document.activeElement.id")
    assert_current_path event_path(@event, q: "wiedź")
    assert_equal "original", page.evaluate_script("window.searchDocument")
  ensure
    page.execute_script("if(window.searchOriginalFetch) window.fetch=window.searchOriginalFetch")
  end

  test "other members votes refresh while search stays focused without replacing an unfinished proposal" do
    fill_in "Twoja propozycja", with: "Niedokończony pomysł"
    fill_in "Szukaj propozycji", with: "wiedź"
    assert_selector ".option-card", count: 2
    assert_selector "#option-#{@witcher.id} .option-count", text: "0"
    Voting.cast!(event: @event, participant: create_participant, option_id: @witcher.id)
    assert_selector "#option-#{@witcher.id} .option-count", text: "1", wait: 20
    assert_equal "q", page.evaluate_script("document.activeElement.id")
    assert_field "Szukaj propozycji", with: "wiedź"
    assert_field "Twoja propozycja", with: "Niedokończony pomysł"
    assert_current_path event_path(@event, q: "wiedź")
    assert_equal "original", page.evaluate_script("window.searchDocument")
  end

  test "browser autofill keeps the search background and horizontal text spacing" do
    fill_in "Szukaj propozycji", with: "wiedź"
    assert_selector ".option-card", count: 2
    browser = page.driver.browser
    browser.execute_cdp("DOM.enable")
    browser.execute_cdp("CSS.enable")
    root = browser.execute_cdp("DOM.getDocument").fetch("root").fetch("nodeId")
    node = browser.execute_cdp("DOM.querySelector", nodeId: root, selector: "input[type=search]").fetch("nodeId")
    browser.execute_cdp("CSS.forcePseudoState", nodeId: node, forcedPseudoClasses: [ "autofill" ])
    assert page.evaluate_script("document.querySelector('input[type=search]').matches(':autofill')")
    styles = page.evaluate_script(<<~JS)
      (()=>{
        const input=getComputedStyle(document.querySelector('input[type=search]'));
        return {shadow:input.boxShadow,left:parseFloat(input.paddingLeft),right:parseFloat(input.paddingRight),radius:parseFloat(input.borderRadius),outline:input.outlineStyle,fill:input.webkitTextFillColor};
      })()
    JS
    assert_includes styles.fetch("shadow"), "rgb(11, 14, 26)"
    assert_includes styles.fetch("shadow"), "inset"
    assert_operator styles.fetch("left"), :>=, 8
    assert_operator styles.fetch("right"), :>=, 8
    assert_operator styles.fetch("radius"), :>, 0
    assert_equal "none", styles.fetch("outline")
    assert_equal "rgb(241, 245, 249)", styles.fetch("fill")
    page.execute_script("document.querySelector('.search-form').scrollIntoView({block:'center',behavior:'instant'})")
    save_screenshot(Rails.root.join("tmp/screenshots/search-autofill.png"))
  ensure
    browser&.execute_cdp("CSS.forcePseudoState", nodeId: node, forcedPseudoClasses: []) if node
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
