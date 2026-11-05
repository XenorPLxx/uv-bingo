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
    assert_select "h1", /Wielkie zapowiedzi/
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

  test "server renders user text safely" do
    Voting.cast!(event: @event, participant: @voter, text: '<script>alert("x")</script>')
    get event_path(@event)
    assert_response :success
    assert_select "script", text: 'alert("x")', count: 0
    assert_includes response.body, "&lt;script&gt;"
  end
end
