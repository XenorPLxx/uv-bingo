require "test_helper"

class VotingTest < ActiveSupport::TestCase
  setup do
    @event = create_event
    @voter = create_participant
  end

  test "creating an option spends one vote and the sixth action is rejected" do
    5.times { |i| Voting.cast!(event: @event, participant: @voter, text: "Pomysł #{i}") }
    assert_equal 0, @voter.votes_remaining(@event)
    assert_no_difference [ "Vote.count", "Option.count" ] do
      assert_raises(Voting::Invalid) { Voting.cast!(event: @event, participant: @voter, text: "Szósty") }
    end
  end

  test "repeating a vote is idempotent and options cannot be voted twice" do
    vote = Voting.cast!(event: @event, participant: @voter, text: "Pierwszy")
    assert_no_difference "Vote.count" do
      assert_equal vote, Voting.cast!(event: @event, participant: @voter, option_id: vote.option_id)
    end
  end

  test "normalized duplicate and invalid option never consume a vote" do
    Voting.cast!(event: @event, participant: @voter, text: "  Nowy   Wiedźmin  ")
    assert_raises(ActiveRecord::RecordInvalid) { Voting.cast!(event: @event, participant: @voter, text: "NOWY WIEDŹMIN") }
    assert_raises(ActiveRecord::RecordInvalid) { Voting.cast!(event: @event, participant: @voter, text: "x" * 101) }
    assert_equal 4, @voter.votes_remaining(@event)
  end

  test "the voting interval includes opening and excludes closing" do
    travel_to @event.opens_at - 1.second do
      assert_raises(Voting::Invalid) { Voting.cast!(event: @event, participant: @voter, text: "Za wcześnie") }
    end
    travel_to @event.opens_at do
      Voting.cast!(event: @event, participant: @voter, text: "W sam raz")
    end
    travel_to @event.closes_at do
      assert_raises(Voting::Invalid) { Voting.cast!(event: @event, participant: @voter, text: "Za późno") }
    end
  end

  test "disqualified and foreign event options are unavailable" do
    option = Voting.cast!(event: @event, participant: create_participant, text: "Wykluczona").option
    option.update!(disqualified_at: Time.current)
    assert_raises(ActiveRecord::RecordNotFound) { Voting.cast!(event: @event, participant: @voter, option_id: option.id) }
    other = create_event
    foreign = Voting.cast!(event: other, participant: create_participant, text: "Inne wydarzenie").option
    assert_raises(ActiveRecord::RecordNotFound) { Voting.cast!(event: @event, participant: @voter, option_id: foreign.id) }
  end

  test "votes cannot be edited or destroyed" do
    vote = Voting.cast!(event: @event, participant: @voter, text: "Ostateczny")
    assert_raises(ActiveRecord::ReadOnlyRecord) { vote.update!(slot: 2) }
    assert_raises(ActiveRecord::ReadOnlyRecord) { vote.destroy! }
  end

  test "database rejects a sixth slot even when model validation is bypassed" do
    option = Voting.cast!(event: @event, participant: @voter, text: "Typ").option
    assert_raises(ActiveRecord::StatementInvalid) do
      Vote.transaction(requires_new: true) do
        Vote.insert_all!([ { event_id: @event.id, participant_id: create_participant.id, option_id: option.id, slot: 6, created_at: Time.current } ])
      end
    end
  end
end
