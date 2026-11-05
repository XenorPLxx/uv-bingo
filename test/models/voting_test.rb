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
    assert_raises(Voting::Invalid) { Voting.cast!(event: @event, participant: @voter, option_id: option.id) }
    other = create_event
    foreign = Voting.cast!(event: other, participant: create_participant, text: "Inne wydarzenie").option
    assert_raises(Voting::Invalid) { Voting.cast!(event: @event, participant: @voter, option_id: foreign.id) }
  end

  test "twenty authored proposals is a lifetime event cap independent of vote withdrawals or moderation" do
    options = 20.times.map do |i|
      vote = Voting.cast!(event: @event, participant: @voter, text: "Propozycja #{i}")
      Voting.withdraw!(event: @event, participant: @voter, vote_id: vote.id)
      vote.option
    end
    assert_equal 5, @voter.votes_remaining(@event)
    options.first.update!(disqualified_at: Time.current)
    OptionMerge.call(event: @event, admin: @voter, source_id: options[1].id, target_id: options[2].id, reason: "Duplikat")
    previous_revision = @event.reload.revision
    assert_no_difference [ "Option.count", "Vote.count" ] do
      error = assert_raises(Voting::Invalid) { Voting.cast!(event: @event, participant: @voter, text: "Propozycja 21") }
      assert_match "maksymalnie 20", error.message
    end
    assert_equal previous_revision, @event.reload.revision
    other_option = seed_options(@event, 1).first
    Voting.cast!(event: @event, participant: @voter, option_id: other_option.id)
    assert_equal 4, @voter.votes_remaining(@event)
    other_event = create_event
    Voting.cast!(event: other_event, participant: @voter, text: "Nowe wydarzenie, nowy limit")
    assert_equal 4, @voter.votes_remaining(other_event)
  end

  test "votes cannot be edited or destroyed outside the voting service" do
    vote = Voting.cast!(event: @event, participant: @voter, text: "Mój typ")
    assert_raises(ActiveRecord::ReadOnlyRecord) { vote.update!(slot: 2) }
    assert_raises(ActiveRecord::ReadOnlyRecord) { vote.destroy! }
  end

  test "withdrawing a middle vote preserves its option and frees exactly one reusable slot" do
    votes = 5.times.map { |i| Voting.cast!(event: @event, participant: @voter, text: "Typ #{i}") }
    withdrawn = votes.fetch(1)
    assert_no_difference "Option.count" do
      assert_difference "Vote.count", -1 do
        Voting.withdraw!(event: @event, participant: @voter, vote_id: withdrawn.id)
      end
    end
    assert_equal 1, @voter.votes_remaining(@event)
    assert_equal 0, withdrawn.option.votes.count
    replacement = Voting.cast!(event: @event, participant: @voter, option_id: withdrawn.option_id)
    assert_equal 2, replacement.slot
    assert_equal 0, @voter.votes_remaining(@event)
  end

  test "withdrawal requires ownership event and an open voting window" do
    vote = Voting.cast!(event: @event, participant: @voter, text: "Mój typ")
    assert_no_difference "Vote.count" do
      assert_raises(ActiveRecord::RecordNotFound) { Voting.withdraw!(event: @event, participant: create_participant, vote_id: vote.id) }
      assert_raises(ActiveRecord::RecordNotFound) { Voting.withdraw!(event: create_event, participant: @voter, vote_id: vote.id) }
      travel_to @event.closes_at do
        assert_raises(Voting::Invalid) { Voting.withdraw!(event: @event, participant: @voter, vote_id: vote.id) }
      end
    end
    vote.option.update!(disqualified_at: Time.current)
    Voting.withdraw!(event: @event, participant: @voter, vote_id: vote.id)
    assert_equal 5, @voter.votes_remaining(@event)
  end

  test "simultaneous events have independent five vote allowances" do
    other = create_event
    [ @event, other ].each do |event|
      5.times { |i| Voting.cast!(event: event, participant: @voter, text: "Typ #{i}") }
      assert_equal 0, @voter.votes_remaining(event)
    end
    Voting.withdraw!(event: @event, participant: @voter, vote_id: @voter.votes.where(event: @event).first.id)
    assert_equal 1, @voter.votes_remaining(@event)
    assert_equal 0, @voter.votes_remaining(other)
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
