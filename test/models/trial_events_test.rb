require "test_helper"

class TrialEventsTest < ActiveSupport::TestCase
  test "prepares an unbiased voting trial and a separate live reproducible demo board" do
    voting, board = TrialEvents.prepare!
    assert voting.rehearsal?
    assert board.rehearsal?
    assert voting.voting_open?
    assert_operator voting.created_at, :>, board.created_at
    assert_equal 30, voting.options.count
    assert_equal 0, voting.votes.count
    assert voting.options.group(:participant_id).count.values.all? { |count| count <= Option::PER_PARTICIPANT_LIMIT }
    assert_equal "live", board.phase
    assert_equal 25, board.cells.count
    assert_equal 25, board.votes.count
    assert_equal board.draw.result, BoardDraw.arrange(board.draw.snapshot, board.draw.seed)
    assert_equal board.draw.result, board.cells.pluck(:option_id)
    assert_equal "trial-setup", board.draw.participant.discord_id
    assert_equal 1, board.audit_entries.where(action: "draw").count
    assert_equal 0, Session.count
    assert_equal 0, LoginToken.count
  end

  test "running trial setup again preserves community votes dates and official marks" do
    voting, board = TrialEvents.prepare!
    voter = create_participant
    vote = Voting.cast!(event: voting, participant: voter, text: "Prawdziwa propozycja uczestnika")
    cell = board.cells.first
    BoardActions.mark!(cell: cell, admin: voter, mark: "question", revision: cell.revision)
    closes_at = voting.closes_at
    draw = board.draw.attributes
    travel 1.day do
      assert_no_difference [ "Event.count", "Option.count", "Vote.count", "Draw.count", "Cell.count", "AuditEntry.count", "Participant.count" ] do
        assert_equal [ voting.id, board.id ], TrialEvents.prepare!.map(&:id)
      end
    end
    assert Vote.exists?(vote.id)
    assert_equal closes_at, voting.reload.closes_at
    assert_equal "question", cell.reload.mark
    assert_equal draw, board.draw.reload.attributes
  end
end
