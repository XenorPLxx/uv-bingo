require "test_helper"

class OptionMergeTest < ActiveSupport::TestCase
  setup do
    @event = create_event
    @admin = create_participant
    @source = @event.options.create!(participant: @admin, text: "Nowy zwiastun gry")
    @target = @event.options.create!(participant: @admin, text: "Zwiastun nowej gry")
  end

  test "merge combines distinct voters and refunds only people who voted for both" do
    both = create_participant
    source_only = create_participant
    target_only = create_participant
    source_vote = Voting.cast!(event: @event, participant: source_only, option_id: @source.id)
    duplicate = Voting.cast!(event: @event, participant: both, option_id: @source.id)
    retained = Voting.cast!(event: @event, participant: both, option_id: @target.id)
    Voting.cast!(event: @event, participant: target_only, option_id: @target.id)
    fillers = 4.times.map { |i| @event.options.create!(participant: @admin, text: "Inny pomysł #{i}") }
    fillers.each { |option| Voting.cast!(event: @event, participant: source_only, option_id: option.id) }
    fillers.first(3).each { |option| Voting.cast!(event: @event, participant: both, option_id: option.id) }

    assert_no_difference "Option.count" do
      assert_difference "Vote.count", -1 do
        assert_equal({ transferred_votes: 1, returned_votes: 1 }, merge)
      end
    end
    assert_equal 3, @target.votes.count
    assert_equal 0, @source.votes.count
    assert_equal @target.id, @source.reload.merged_into_id
    assert_equal @target.id, source_vote.reload.option_id
    assert Vote.exists?(retained.id)
    assert_not Vote.exists?(duplicate.id)
    assert_equal 1, both.votes_remaining(@event)
    assert_equal 0, source_only.votes_remaining(@event)
    assert_equal 4, target_only.votes_remaining(@event)
    assert_not_includes @event.options.eligible, @source
    assert_includes @event.options.eligible, @target
    assert_equal "Nowy zwiastun gry", @source.text
    entry = @event.audit_entries.find_by!(action: "merge_options")
    assert_equal @admin, entry.participant
    assert_equal 1, entry.details.fetch("returned_votes")
    assert_equal both.id, entry.details.fetch("refunded_votes").first.fetch("participant_id")
    assert_equal 1, @event.reload.revision

    replacement = Voting.cast!(event: @event, participant: both, option_id: fillers.last.id)
    assert_equal duplicate.slot, replacement.slot
    assert_equal 0, both.votes_remaining(@event)
    assert_raises(Voting::Invalid) { Voting.cast!(event: @event, participant: both, text: "Szósty głos") }
  end

  test "cached votes and subsequent merges resolve to the final retained option" do
    voter = create_participant
    merge
    vote = Voting.cast!(event: @event, participant: voter, option_id: @source.id)
    assert_equal @target.id, vote.option_id
    assert_no_difference "Vote.count" do
      assert_equal vote, Voting.cast!(event: @event, participant: voter, option_id: @target.id)
    end
    final = @event.options.create!(participant: @admin, text: "Docelowa propozycja")
    merge(source: @target, target: final)
    assert_equal final.id, @source.reload.merged_into_id
    assert_equal final.id, @target.reload.merged_into_id
    assert_equal final.id, vote.reload.option_id
    fresh = Voting.cast!(event: @event, participant: create_participant, option_id: @source.id)
    assert_equal final.id, fresh.option_id
    assert_raises(ActiveRecord::RecordInvalid) { Voting.cast!(event: @event, participant: create_participant, text: @source.text) }
  end

  test "self cross event disqualified already merged and invalid reason requests change nothing" do
    foreign = create_event.options.create!(participant: @admin, text: "Z innego wydarzenia")
    assert_no_difference [ "Vote.count", "AuditEntry.count" ] do
      assert_raises(Voting::Invalid) { merge(target: @source) }
      assert_raises(ActiveRecord::RecordNotFound) { merge(target: foreign) }
      assert_raises(ActiveRecord::RecordNotFound) { merge(source: foreign) }
      assert_raises(Voting::Invalid) { merge(reason: " ") }
      assert_raises(Voting::Invalid) { merge(reason: "x" * 201) }
      @target.update!(disqualified_at: Time.current)
      assert_raises(Voting::Invalid) { merge }
      @target.update!(disqualified_at: nil)
      @source.update!(disqualified_at: Time.current)
      assert_raises(Voting::Invalid) { merge }
    end
    @source.update!(disqualified_at: nil)
    merge
    assert_no_difference "AuditEntry.count" do
      assert_raises(Voting::Invalid) { merge }
      assert_raises(Voting::Invalid) { merge(source: @target, target: @source) }
    end
  end

  test "closed voting can be merged but a drawn or archived event cannot be changed" do
    seed_options(@event, 25)
    both = create_participant
    Voting.cast!(event: @event, participant: both, option_id: @source.id)
    Voting.cast!(event: @event, participant: both, option_id: @target.id)
    Voting.cast!(event: @event, participant: create_participant, option_id: @source.id)
    Voting.cast!(event: @event, participant: create_participant, option_id: @target.id)
    @event.update!(closes_at: 1.second.ago)
    merge
    assert_equal 4, both.votes_remaining(@event)
    assert_raises(Voting::Invalid) { Voting.cast!(event: @event, participant: both, text: "Po zamknięciu") }
    draw = BoardDraw.call(event: @event, admin: @admin)
    assert_not_includes draw.snapshot.map { |item| item.fetch("id") }, @source.id
    assert_equal 3, draw.snapshot.find { |item| item.fetch("id") == @target.id }.fetch("votes")
    assert_equal @target.id, @event.cells.find_by!(position: 12).option_id
    assert_equal 3, @event.cells.find_by!(position: 12).votes_count
    assert_no_difference [ "Vote.count", "AuditEntry.count" ] do
      options = @event.options.eligible.first(2)
      assert_raises(Voting::Invalid) { merge(source: options.first, target: options.last) }
    end
    other = create_event(state: "archived")
    options = 2.times.map { |i| other.options.create!(participant: @admin, text: "Typ #{i}") }
    assert_raises(Voting::Invalid) { OptionMerge.call(event: other, admin: @admin, source_id: options.first.id, target_id: options.last.id, reason: "Duplikat") }
  end

  test "a failed audit rolls back votes refunds and merge tracking" do
    voter = create_participant
    Voting.cast!(event: @event, participant: voter, option_id: @source.id)
    Voting.cast!(event: @event, participant: voter, option_id: @target.id)
    assert_raises(ActiveRecord::NotNullViolation) do
      OptionMerge.call(event: @event, admin: Participant.new, source_id: @source.id, target_id: @target.id, reason: "Duplikat")
    end
    assert_equal 1, @source.votes.count
    assert_equal 1, @target.votes.count
    assert_nil @source.reload.merged_into_id
    assert_equal 3, voter.votes_remaining(@event)
    assert_equal 0, @event.reload.revision
    assert_equal 0, @event.audit_entries.count
  end

  private

  def merge(source: @source, target: @target, reason: "Powtarzająca się propozycja")
    OptionMerge.call(event: @event, admin: @admin, source_id: source.id, target_id: target.id, reason: reason)
  end
end
