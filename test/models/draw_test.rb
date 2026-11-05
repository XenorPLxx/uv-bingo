require "test_helper"

class DrawTest < ActiveSupport::TestCase
  setup do
    @event = create_event
    @admin = create_participant
    @options = seed_options(@event)
  end

  test "top option is centered and top 25 are selected reproducibly" do
    5.times { Voting.cast!(event: @event, participant: create_participant, option_id: @options.last.id) }
    travel_to @event.closes_at do
      draw = BoardDraw.call(event: @event, admin: @admin)
      assert_equal 25, @event.cells.count
      assert_equal @options.last.id, @event.cells.find_by!(position: 12).option_id
      assert_equal 25, draw.result.uniq.length
      assert_equal draw.result, BoardDraw.arrange(draw.reload.snapshot, draw.seed)
      assert_equal draw.snapshot_digest, Digest::SHA256.hexdigest(JSON.generate(draw.snapshot))
      assert_no_difference [ "Draw.count", "Cell.count", "AuditEntry.count" ] do
        assert_equal draw, BoardDraw.call(event: Event.find(@event.id), admin: @admin)
      end
    end
  end

  test "ties at center and cutoff use saved random seed" do
    snapshot = 30.times.map { |i| { "id" => i + 1, "text" => "Typ #{i}", "votes" => 1 } }
    one = BoardDraw.arrange(snapshot, "seed-one")
    assert_equal one, BoardDraw.arrange(snapshot.reverse, "seed-one")
    two = BoardDraw.arrange(snapshot, "seed-two")
    assert_not_equal one, two
    assert_not_equal one.sort, two.sort
  end

  test "draw is refused before closing or below 25 eligible options" do
    assert_raises(Voting::Invalid) { BoardDraw.call(event: @event, admin: @admin) }
    @event.options.limit(6).update_all(disqualified_at: Time.current)
    travel_to @event.closes_at do
      assert_raises(Voting::Invalid) { BoardDraw.call(event: @event, admin: @admin) }
    end
    assert_equal 0, @event.cells.count
  end

  test "snapshot and cells keep their original text" do
    travel_to @event.closes_at do
      draw = BoardDraw.call(event: @event, admin: @admin)
      cell = @event.cells.first
      original = cell.text
      cell.option.update!(text: "Inna nazwa")
      assert_equal original, cell.reload.text
      assert_equal original, draw.snapshot.find { |item| item["id"] == cell.option_id }["text"]
    end
  end
end
