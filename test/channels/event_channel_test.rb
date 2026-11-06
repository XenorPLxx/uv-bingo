require "test_helper"

class EventChannelTest < ActionCable::Channel::TestCase
  setup { @event = create_event }

  test "open pages are counted per event and every change is broadcast" do
    stream = "event:#{@event.id}"
    assert_broadcast_on(stream, viewers: 1) { subscribe(event_id: @event.id) }
    assert subscription.confirmed?
    assert_has_stream stream
    first = subscription
    assert_broadcast_on(stream, viewers: 2) { subscribe(event_id: @event.id) }
    assert_equal 2, EventChannel.viewers(@event.id)
    assert_broadcast_on(stream, viewers: 1) { unsubscribe }
    assert_broadcast_on(stream, viewers: 0) { first.unsubscribe_from_channel }
    assert_equal 0, EventChannel.viewers(@event.id)
    assert_equal 0, EventChannel.change_viewers(@event.id, -1), "Counts never go below zero"
  end

  test "unknown events are rejected without counting a viewer" do
    missing = Event.maximum(:id).to_i + 1
    assert_no_broadcasts("event:#{missing}") { subscribe(event_id: missing) }
    assert subscription.rejected?
    assert_equal 0, EventChannel.viewers(missing)
  end

  test "a confirmed subscriber can get the count even if it missed the join broadcast" do
    subscribe(event_id: @event.id)
    assert_empty transmissions
    perform :viewer_count
    assert_equal({ "viewers" => 1 }, transmissions.last)
  ensure
    unsubscribe
  end

  test "delayed viewer broadcasts send the current count and preserve board changes" do
    subscribe(event_id: @event.id)
    first = subscription
    subscribe(event_id: @event.id)
    subscription.send(:receive_update, { "viewers" => 1 })
    assert_equal({ "viewers" => 2 }, transmissions.last)
    first.unsubscribe_from_channel
    subscription.send(:receive_update, { "viewers" => 2 })
    assert_equal({ "viewers" => 1 }, transmissions.last)
    subscription.send(:receive_update, { "revision" => 42 })
    assert_equal({ "revision" => 42 }, transmissions.last)
  ensure
    unsubscribe
  end

  test "events are counted independently and repeated cleanup does not remove another viewer" do
    subscribe(event_id: @event.id)
    first = subscription
    subscribe(event_id: @event.id)
    second = subscription
    other = create_event
    subscribe(event_id: other.id)
    assert_equal 2, EventChannel.viewers(@event.id)
    assert_equal 1, EventChannel.viewers(other.id)
    first.unsubscribe_from_channel
    first.unsubscribe_from_channel
    assert_equal 1, EventChannel.viewers(@event.id)
    assert_equal 1, EventChannel.viewers(other.id)
  ensure
    second&.unsubscribe_from_channel
    unsubscribe
  end
end
