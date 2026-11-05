require "test_helper"

class BoardActionsTest < ActiveSupport::TestCase
  setup do
    @event = create_event
    @admin = create_participant
    @voter = create_participant
    seed_options(@event, 25)
    travel_to @event.closes_at do
      BoardDraw.call(event: @event, admin: @admin)
    end
    @event.update!(state: "live")
    @cell = @event.cells.first
  end

  test "a participant has one replaceable proposal per cell revision" do
    BoardActions.propose!(cell: @cell, participant: @voter, mark: "question", revision: 0)
    BoardActions.propose!(cell: @cell, participant: @voter, mark: "cross", revision: 0)
    assert_equal 1, @cell.proposals.count
    assert_equal "cross", @cell.proposals.first.mark
    assert_equal 5, @voter.votes_remaining(@event)
    BoardActions.propose!(cell: @cell, participant: @voter, mark: "blank", revision: 0)
    assert_equal 0, @cell.proposals.count
  end

  test "admin decision archives old proposals and rejects stale writes" do
    BoardActions.propose!(cell: @cell, participant: @voter, mark: "question", revision: 0)
    BoardActions.mark!(cell: @cell, admin: @admin, mark: "cross", revision: 0)
    assert_equal "cross", @cell.reload.mark
    assert_empty @cell.current_proposals
    assert_equal 1, @cell.proposals.count
    assert_raises(Voting::Invalid) { BoardActions.mark!(cell: @cell, admin: @admin, mark: "blank", revision: 0) }
    assert_raises(Voting::Invalid) { BoardActions.propose!(cell: @cell, participant: @voter, mark: "question", revision: 0) }
    assert_equal "cross", @cell.reload.mark
    assert_equal "mark", @event.audit_entries.last.action
  end

  test "archived events reject both proposals and marks" do
    @event.update!(state: "archived")
    assert_raises(Voting::Invalid) { BoardActions.propose!(cell: @cell, participant: @voter, mark: "cross", revision: 0) }
    assert_raises(Voting::Invalid) { BoardActions.mark!(cell: @cell, admin: @admin, mark: "cross", revision: 0) }
  end

  test "only crosses complete bingo lines" do
    @event.cells.where(position: 0..4).update_all(mark: "question")
    assert_empty @event.reload.completed_lines
    @event.cells.where(position: 0..4).update_all(mark: "cross")
    assert_equal [ [ 0, 1, 2, 3, 4 ] ], @event.reload.completed_lines
  end
end
