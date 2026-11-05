require "test_helper"

class WebsiteTest < ActionDispatch::IntegrationTest
  setup do
    @event = create_event
    @voter = create_participant
  end

  test "public pages render and cannot vote without authentication" do
    get root_path
    assert_response :success
    assert_select "html[lang=pl]"
    assert_select "h1", @event.title
    assert_no_difference "Vote.count" do
      post event_options_path(@event), params: { text: "Pomysł" }
    end
    assert_redirected_to sign_in_path
    get admin_root_path
    assert_response :forbidden
  end

  test "login is not consumed by GET and cannot be reused or used after expiration" do
    raw = LoginToken.issue!(participant: @voter, interaction_id: "login-test")
    get "/login", params: { token: raw }
    assert_nil LoginToken.last.consumed_at
    follow_redirect!
    assert_response :success
    assert_match @voter.display_name, response.body
    post confirm_login_path
    assert LoginToken.last.consumed_at
    assert_equal 1, @voter.sessions.active.count
    post event_options_path(@event), params: { text: "Mój typ" }
    assert_equal 1, @voter.votes.count
    get "/login", params: { token: raw }
    assert_redirected_to sign_in_path
    expired = LoginToken.issue!(participant: @voter, interaction_id: "expired")
    travel 11.minutes do
      get "/login", params: { token: expired }
      assert_redirected_to sign_in_path
    end
  end

  test "voter cannot invoke admin operations or forge role" do
    sign_in_as(@voter)
    post draw_admin_event_path(@event), params: { admin: true }
    assert_response :forbidden
    patch admin_event_path(@event), params: { event: { title: "Zmienione" } }
    assert_response :forbidden
    assert_equal "TGA Test", @event.reload.title
  end

  test "admin can manage events but cannot reopen or moderate a drawn event" do
    with_env ADMIN_DISCORD_IDS: @voter.discord_id do
      sign_in_as(@voter)
      get admin_event_path(@event)
      assert_response :success
      seed_options(@event, 25)
      travel_to @event.closes_at do
        post draw_admin_event_path(@event)
        assert_response :redirect
        assert @event.reload.draw
        get reveal_event_path(@event)
        assert_response :success
        patch admin_event_path(@event), params: { event: { closes_at: 2.days.from_now } }
        assert_equal "Ustawienia zostały zamknięte po losowaniu.", flash[:alert]
        post transition_admin_event_path(@event), params: { state: "live" }
        assert_equal "live", @event.reload.state
        get event_path(@event)
        assert_response :success
        assert_select ".bingo-cell", 25
        get presentation_event_path(@event)
        assert_response :success
        assert_select ".proposal-button", 50
        assert_select ".decision-button", 50
        assert_select "dialog", 0
        get reveal_event_path(@event)
        assert_select ".proposal-button, .decision-button", 0
        get state_event_path(@event), params: { presentation: "1" }
        assert_response :success
        assert_equal "live", response.parsed_body["phase"]
      end
    end
  end

  test "event navigation exposes simultaneous events and each voting budget" do
    other = create_event(title: "Drugie wydarzenie")
    get root_path
    assert_select "nav[aria-label=Wydarzenia] a[href=?]", event_path(@event)
    assert_select "nav[aria-label=Wydarzenia] a[href=?]", event_path(other)
    get event_path(@event)
    assert_select "nav[aria-label=Wydarzenia] a[aria-current=page][href=?]", event_path(@event)
    assert_select "nav[aria-label=Wydarzenia] a[href=?]", event_path(other)
  end

  test "a signed in participant can withdraw only their own vote without deleting the option" do
    own_vote = Voting.cast!(event: @event, participant: @voter, text: "Mój typ")
    other_vote = Voting.cast!(event: @event, participant: create_participant, text: "Cudzy typ")
    delete event_vote_path(@event, own_vote)
    assert_redirected_to sign_in_path
    sign_in_as(@voter)
    assert_no_difference "Vote.count" do
      delete event_vote_path(@event, other_vote)
      assert_response :not_found
    end
    assert_difference "Vote.count", -1 do
      delete event_vote_path(@event, own_vote)
      assert_redirected_to event_path(@event, anchor: "options")
    end
    assert Option.exists?(own_vote.option_id)
    assert_equal 5, @voter.votes_remaining(@event)
  end

  test "inline board requests enforce roles revisions and retain presentation fallback" do
    admin = create_participant
    seed_options(@event, 25)
    @event.update!(closes_at: 1.second.ago)
    BoardDraw.call(event: @event, admin: admin)
    @event.update!(state: "live")
    cell = @event.cells.first
    action = { cell_id: cell.id, mark: "question", revision: cell.revision, presentation: "1" }
    post event_proposals_path(@event), params: action, as: :json
    assert_response :unauthorized
    with_env ADMIN_DISCORD_IDS: admin.discord_id do
      sign_in_as(@voter)
      get presentation_event_path(@event)
      assert_select ".proposal-button", 50
      assert_select ".decision-button", 0
      post event_proposals_path(@event), params: action, as: :json
      assert_response :success
      assert_equal "question", cell.proposals.last.mark
      post mark_admin_event_path(@event), params: action, as: :json
      assert_response :forbidden
      sign_in_as(admin)
      post mark_admin_event_path(@event), params: action, as: :json
      assert_response :success
      assert_equal "question", cell.reload.mark
      post event_proposals_path(@event), params: action, as: :json
      assert_response :unprocessable_entity
      assert_match "Pole zostało zmienione", response.parsed_body.fetch("error")
      post mark_admin_event_path(@event), params: action.merge(mark: "blank", revision: cell.revision)
      assert_redirected_to presentation_event_path(@event)
    end
  end

  test "voting responds without redirects and returns refreshed filtered voting fragments" do
    options = seed_options(@event, 6)
    post event_votes_path(@event), params: { option_id: options.first.id }, as: :json
    assert_response :unauthorized
    sign_in_as(@voter)
    previous_revision = @event.reload.revision
    post event_votes_path(@event), params: { option_id: options.last.id }, as: :json
    assert_response :success
    assert_match "Głos zapisany", response.parsed_body.fetch("message")
    get state_event_path(@event), params: { revision: previous_revision, phase: "open", q: "numer 6" }
    assert_response :success
    fragments = response.parsed_body.fetch("voting")
    rows = Nokogiri::HTML.fragment(fragments.fetch("options"))
    assert_equal [ "option-#{options.last.id}" ], rows.css(".option-card").map { |row| row["id"] }
    assert rows.at_css(".option-card.selected")
    assert_equal "2", rows.at_css(".option-count").text
    assert_includes fragments.fetch("ballot"), "1<small>/5</small>"
    assert_equal true, fragments.fetch("can_add")
    assert_equal 6, fragments.fetch("option_count")
    current_revision = response.parsed_body.fetch("revision")
    get state_event_path(@event), params: { revision: current_revision, phase: "open" }
    assert_nil response.parsed_body["voting"]
    get state_event_path(@event), params: { revision: current_revision, phase: "open", refresh: "1" }
    assert response.parsed_body["voting"]
    options.first(4).each { |option| Voting.cast!(event: @event, participant: @voter, option_id: option.id) }
    assert_no_difference "Vote.count" do
      post event_votes_path(@event), params: { option_id: options[4].id }, as: :json
      assert_response :unprocessable_entity
      assert response.parsed_body.fetch("error").present?
    end
    delete event_vote_path(@event, @voter.votes.first), as: :json
    assert_response :success
    assert_match "Głos cofnięty", response.parsed_body.fetch("message")
    post event_options_path(@event), params: { text: "Nowa propozycja bez przeładowania" }, as: :json
    assert_response :success
    assert_match "Propozycja dodana", response.parsed_body.fetch("message")
  end

  test "HTML voting fallback puts notices and errors above proposals and retains search" do
    option = seed_options(@event, 1).first
    sign_in_as(@voter)
    post event_votes_path(@event), params: { option_id: option.id, q: "numer" }
    assert_redirected_to event_path(@event, q: "numer", anchor: "options")
    follow_redirect!
    assert_select ".voting-feedback .flash.notice", text: /Głos zapisany/
    assert_select ".page-container > .flash", 0
    @event.update!(closes_at: 1.second.ago)
    delete event_vote_path(@event, @voter.votes.first), params: { q: "numer" }
    assert_redirected_to event_path(@event, q: "numer", anchor: "options")
    follow_redirect!
    assert_select ".voting-feedback .flash.alert"
    assert_select ".page-container > .flash", 0
    assert_equal 1, @voter.votes.count
  end

  test "only admins can merge options and merged sources cannot be restored or drawn" do
    source, target = seed_options(@event, 2)
    Voting.cast!(event: @event, participant: @voter, option_id: source.id)
    Voting.cast!(event: @event, participant: @voter, option_id: target.id)
    merge_params = { source_id: source.id, target_id: target.id, reason: "Powtórzona propozycja" }
    sign_in_as(@voter)
    assert_no_difference "Vote.count" do
      post merge_admin_event_path(@event), params: merge_params
      assert_response :forbidden
    end
    with_env ADMIN_DISCORD_IDS: @voter.discord_id do
      get admin_event_path(@event)
      assert_select ".merge-form"
      post merge_admin_event_path(@event), params: merge_params
      assert_redirected_to admin_event_path(@event, anchor: "moderation")
      assert_equal target.id, source.reload.merged_into_id
      assert_equal 4, @voter.votes_remaining(@event)
      get event_path(@event)
      assert_select "#option-#{source.id}", 0
      assert_select "#option-#{target.id}.selected", 1
      get admin_event_path(@event)
      assert_select "#moderation-option-#{source.id} .merge-destination a[href=?]", "#moderation-option-#{target.id}"
      assert_select "#moderation-option-#{source.id} .moderation-form", 0
      post moderate_admin_event_path(@event), params: { option_id: source.id, operation: "restore", reason: "Nie przywracaj" }
      assert_equal target.id, source.reload.merged_into_id
      assert_match "została połączona", flash[:alert]
      25.times { |i| Voting.cast!(event: @event, participant: create_participant, text: "Dodatkowa propozycja #{i}") }
      @event.update!(closes_at: 1.second.ago)
      BoardDraw.call(event: @event, admin: @voter)
      get admin_event_path(@event)
      assert_select ".merge-form", 0
      assert_no_difference "AuditEntry.count" do
        post merge_admin_event_path(@event), params: merge_params
      end
    end
  end

  test "public proposals show current vote totals and reorder after a withdrawal" do
    first, popular, tied, zero, hidden = [ "Pierwsza propozycja", "Popularna propozycja", "Remis", "Bez głosów", "Wykluczona" ].map do |text|
      @event.options.create!(participant: @voter, text: text)
    end
    own_vote = Voting.cast!(event: @event, participant: @voter, option_id: popular.id)
    { first => 2, popular => 2, tied => 2, hidden => 5 }.each do |option, count|
      count.times { Voting.cast!(event: @event, participant: create_participant, option_id: option.id) }
    end
    hidden.update!(disqualified_at: Time.current)
    get event_path(@event)
    assert_select ".options-list .option-card" do |rows|
      assert_equal [ popular, first, tied, zero ].map { |option| "option-#{option.id}" }, rows.map { |row| row["id"] }
    end
    assert_select ".option-count" do |counts|
      assert_equal [ "3", "2", "2", "0" ], counts.map { |count| count.text.strip }
    end
    assert_select ".option-number, .vote-total", 0
    get event_path(@event), params: { q: "Remis" }
    assert_select ".option-card", 1
    assert_select "#option-#{tied.id} .option-count", "2"
    get state_event_path(@event)
    revision = response.parsed_body.fetch("revision")
    sign_in_as(@voter)
    delete event_vote_path(@event, own_vote)
    get state_event_path(@event)
    assert_equal revision + 1, response.parsed_body.fetch("revision")
    get event_path(@event)
    assert_select ".options-list .option-card" do |rows|
      assert_equal [ first, popular, tied, zero ].map { |option| "option-#{option.id}" }, rows.map { |row| row["id"] }
    end
    assert_select "#option-#{popular.id} .option-count", "2"
  end

  test "event deletion requires admin access and exact typed confirmation" do
    option = Voting.cast!(event: @event, participant: @voter, text: "Propozycja do usunięcia").option
    get deletion_admin_event_path(@event)
    assert_response :forbidden
    delete admin_event_path(@event), params: { confirmation: @event.slug }
    assert_response :forbidden
    sign_in_as(@voter)
    delete admin_event_path(@event), params: { confirmation: @event.slug, admin: true }
    assert_response :forbidden
    with_env ADMIN_DISCORD_IDS: @voter.discord_id do
      get admin_event_path(@event)
      assert_select "a[href=?]", deletion_admin_event_path(@event)
      assert_no_difference "Event.count" do
        get deletion_admin_event_path(@event)
        assert_response :success
        assert_select ".deletion-form input[name=confirmation][required][pattern=?]", @event.slug
        delete admin_event_path(@event), params: { confirmation: "niepoprawne" }
        assert_response :unprocessable_entity
      end
      assert Option.exists?(option.id)
      assert_difference "Event.count", -1 do
        delete admin_event_path(@event), params: { confirmation: @event.slug }
        assert_redirected_to admin_root_path
      end
      assert_not Option.exists?(option.id)
      assert Participant.exists?(@voter.id)
      get event_path(@event)
      assert_response :not_found
      get state_event_path(@event)
      assert_response :not_found
      get root_path, params: { removed: "1" }
      assert_response :success
      assert_match "Wydarzenie zostało usunięte", response.body
    end
  end

  test "server renders user text safely" do
    Voting.cast!(event: @event, participant: @voter, text: '<script>alert("x")</script>')
    get event_path(@event)
    assert_response :success
    assert_select "script", text: 'alert("x")', count: 0
    assert_includes response.body, "&lt;script&gt;"
  end

  test "stale disqualified options return a local validation message and refresh away" do
    option = seed_options(@event, 1).first
    sign_in_as(@voter)
    get event_path(@event)
    assert_select "#option-#{option.id}"
    option.update!(disqualified_at: Time.current)
    assert_no_difference "Vote.count" do
      post event_votes_path(@event), params: { option_id: option.id }, as: :json
      assert_response :unprocessable_entity
      assert_match "nie jest już dostępna", response.parsed_body.fetch("error")
      post event_votes_path(@event), params: { option_id: option.id }
      assert_redirected_to event_path(@event, anchor: "options")
      follow_redirect!
      assert_select ".voting-feedback .alert", text: /nie jest już dostępna/
      assert_select "#option-#{option.id}", 0
    end
  end

  test "proposal cap hides only proposal submission and keeps existing votes available" do
    20.times { |i| @event.options.create!(participant: @voter, text: "Moja propozycja #{i}") }
    other = seed_options(@event, 1).first
    sign_in_as(@voter)
    get event_path(@event)
    assert_select ".authored-option-count", text: /20\/20/
    assert_select ".add-panel textarea", 0
    assert_select "#option-#{other.id} button"
    assert_no_difference [ "Option.count", "Vote.count" ] do
      post event_options_path(@event), params: { text: "Ponad limit" }, as: :json
      assert_response :unprocessable_entity
      assert_match "maksymalnie 20", response.parsed_body.fetch("error")
    end
    post event_votes_path(@event), params: { option_id: other.id }, as: :json
    assert_response :success
    get state_event_path(@event), params: { refresh: "1" }
    assert_equal false, response.parsed_body.dig("voting", "can_add")
    assert_match "Osiągnięto limit 20", response.parsed_body.dig("voting", "add_option")
  end

  test "unchanged live board polls do not render board HTML and changed revisions do" do
    seed_options(@event, 25)
    @event.update!(closes_at: 1.second.ago)
    BoardDraw.call(event: @event, admin: @voter)
    @event.update!(state: "live")
    rendered = []
    observer = ->(_name, _started, _finished, _id, payload) { rendered << payload[:identifier] }
    ActiveSupport::Notifications.subscribed(observer, "render_partial.action_view") do
      get state_event_path(@event), params: { presentation: "1", phase: "live", revision: @event.revision }
    end
    assert_response :success
    assert_equal({ "phase" => "live", "revision" => @event.revision }, response.parsed_body)
    assert_empty rendered
    cell = @event.cells.first
    BoardActions.mark!(cell: cell, admin: @voter, mark: "cross", revision: cell.revision)
    get state_event_path(@event), params: { presentation: "1", phase: "live", revision: @event.revision - 1 }
    assert_response :success
    assert_match "mark-cross", response.parsed_body.fetch("html")
    @event.update!(state: "archived")
    get state_event_path(@event), params: { presentation: "1", phase: "live", revision: @event.revision }
    assert_equal "archived", response.parsed_body.fetch("phase")
    assert response.parsed_body["html"]
  end

  test "CSP allows only local assets nonce scripts and the same host websocket" do
    get event_path(@event)
    assert_response :success
    header = response.headers.fetch("Content-Security-Policy")
    nonce = Nokogiri::HTML(response.body).at_css('meta[name="csp-nonce"]')["content"]
    assert nonce.present?
    assert_includes header, "script-src 'self' 'nonce-#{nonce}'"
    assert_includes header, "script-src-attr 'none'"
    assert_includes header, "style-src 'self'"
    assert_includes header, "connect-src 'self' ws://www.example.com"
    assert_includes header, "object-src 'none'"
    assert_includes header, "frame-ancestors 'none'"
    assert_not_includes header, "unsafe-inline"
    assert_not_includes header, "unsafe-eval"
    assert_select "script[type=importmap][nonce=?]", nonce
    assert_select "script[type=module][nonce=?]", nonce
    get event_path(@event)
    other_nonce = Nokogiri::HTML(response.body).at_css('meta[name="csp-nonce"]')["content"]
    assert_not_equal nonce, other_nonce
    get "/cable"
    assert_response :not_found
    assert_includes response.headers.fetch("Content-Security-Policy"), "connect-src 'self' ws://www.example.com"
  end
end
