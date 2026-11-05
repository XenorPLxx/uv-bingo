require "test_helper"

class AdminEventsTest < ActionDispatch::IntegrationTest
  setup do
    @event = create_event
    @admin = create_participant
    @previous_admins = ENV["ADMIN_DISCORD_IDS"]
    ENV["ADMIN_DISCORD_IDS"] = @admin.discord_id
    sign_in_as(@admin)
  end

  teardown do
    ENV["ADMIN_DISCORD_IDS"] = @previous_admins
  end

  test "invalid creation keeps all form values on the new event form" do
    attributes = { title: "Zachowany tytuł", slug: "zachowany-adres", description: "Zachowany opis", opens_at: "2026-12-04T20:00", closes_at: "2026-12-03T20:00", rehearsal: "1" }
    assert_no_difference [ "Event.count", "AuditEntry.count" ] do
      post admin_events_path, params: { event: attributes }
      assert_response :unprocessable_entity
    end
    assert_select "h1", "Nowe wydarzenie"
    assert_select "form[action=?] input[name='event[title]'][value=?]", admin_events_path, attributes[:title]
    assert_select "input[name='event[slug]'][value=?]", attributes[:slug]
    assert_select "textarea[name='event[description]']", attributes[:description]
    assert_select "input[name='event[rehearsal]'][checked]"
    assert_select ".flash.alert"
  end

  test "invalid settings retain submitted values without changing saved dates or title" do
    old_title = @event.title
    old_closing = @event.closes_at
    patch admin_event_path(@event), params: { event: { title: "Zachowane ustawienia", opens_at: "", closes_at: "2026-12-03T20:00" } }
    assert_response :unprocessable_entity
    assert_select ".settings-panel[open] input[name='event[title]'][value='Zachowane ustawienia']"
    assert_select ".settings-panel input[name='event[opens_at]']" do |inputs|
      assert inputs.first["value"].blank?
    end
    assert_select "h1", old_title
    assert_equal old_title, @event.reload.title
    assert_equal old_closing, @event.closes_at
    assert_equal 0, @event.audit_entries.count
  end

  test "invalid moderation and merging remain in admin with their form inputs" do
    source, target = seed_options(@event, 2)
    post moderate_admin_event_path(@event), params: { option_id: source.id, text: "Zachowana korekta", reason: "xx", operation: "correct" }
    assert_response :unprocessable_entity
    assert_select "#moderation-option-#{source.id} details[open] input[name=text][value='Zachowana korekta']"
    assert_select "#moderation-option-#{source.id} input[name=reason][value=xx]"
    assert_select "#moderation-option-#{source.id} select[name=operation] option[value=correct][selected]"
    assert_not_equal "Zachowana korekta", source.reload.text
    post merge_admin_event_path(@event), params: { source_id: source.id, target_id: target.id, reason: "xx" }
    assert_response :unprocessable_entity
    assert_select ".merge-panel[open] input[name=reason][value=xx]"
    assert_select ".merge-panel select[name=source_id] option[value=?][selected]", source.id.to_s
    assert_select ".merge-panel select[name=target_id] option[value=?][selected]", target.id.to_s
    assert_nil source.reload.merged_into_id
  end

  test "draw action requires twenty five eligible proposals with at least one vote" do
    options = seed_options(@event, 26)
    @event.votes.where(option: options.last(2)).delete_all
    @event.update!(closes_at: 1.second.ago)
    get admin_event_path(@event)
    assert_select "form[action=?] button[disabled]", draw_admin_event_path(@event)
    assert_select ".admin-actions .fineprint strong", "24"
    post draw_admin_event_path(@event)
    assert_redirected_to admin_event_path(@event)
    assert_match "25 propozycji z głosami", flash[:alert]
    assert_nil @event.reload.draw
    @event.update!(closes_at: 1.hour.from_now)
    Voting.cast!(event: @event, participant: create_participant, option_id: options.last.id)
    get admin_event_path(@event)
    assert_select "form[action=?] button[disabled]", draw_admin_event_path(@event)
    @event.update!(closes_at: 1.second.ago)
    get admin_event_path(@event)
    assert_select "form[action=?] button:not([disabled])", draw_admin_event_path(@event)
    post draw_admin_event_path(@event)
    assert_redirected_to reveal_event_path(@event)
    assert_equal 25, @event.cells.count
  end
end
