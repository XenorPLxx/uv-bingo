require "test_helper"

class EventDeletionTest < ActiveSupport::TestCase
  setup do
    @event = create_event
    @admin = create_participant
    @voter = create_participant
    source, target = seed_options(@event, 26).first(2)
    Voting.cast!(event: @event, participant: @voter, option_id: source.id)
    Voting.cast!(event: @event, participant: @voter, option_id: target.id)
    OptionMerge.call(event: @event, admin: @admin, source_id: source.id, target_id: target.id, reason: "Duplikat")
    @event.update!(closes_at: 1.second.ago)
    BoardDraw.call(event: @event, admin: @admin)
    @event.update!(state: "live")
    cell = @event.cells.first
    BoardActions.propose!(cell: cell, participant: @voter, mark: "question", revision: 0)
    BoardActions.mark!(cell: cell, admin: @admin, mark: "cross", revision: 0)
    BoardActions.propose!(cell: cell, participant: @voter, mark: "cross", revision: 1)
  end

  test "confirmed deletion removes only the chosen event and all its related data" do
    other = create_event
    other_vote = Voting.cast!(event: other, participant: @voter, text: "Inne wydarzenie")
    other_cell = other.cells.create!(option: other_vote.option, position: 0, text: "Inne pole", votes_count: 1)
    other_proposal = other_cell.proposals.create!(participant: @voter, revision: 0, mark: "question")
    other_audit = other.audit_entries.create!(participant: @admin, action: "create_event", details: {})
    @voter.sessions.create!(expires_at: 1.day.from_now)
    LoginToken.issue!(participant: @voter, interaction_id: SecureRandom.uuid)
    cell_ids = @event.cells.pluck(:id)
    event_id = @event.id
    assert_no_difference [ "Participant.count", "Session.count", "LoginToken.count" ] do
      EventDeletion.call(event: @event, confirmation: @event.slug)
    end
    assert_not Event.exists?(event_id)
    [ Option, Vote, Cell, Draw, AuditEntry ].each do |model|
      assert_equal 0, model.where(event_id: event_id).count, "#{model.name} records must be removed"
    end
    assert_equal 0, Proposal.where(cell_id: cell_ids).count
    assert Event.exists?(other.id)
    assert Vote.exists?(other_vote.id)
    assert Cell.exists?(other_cell.id)
    assert Proposal.exists?(other_proposal.id)
    assert AuditEntry.exists?(other_audit.id)
    assert_equal 4, @voter.votes_remaining(other)
  end

  test "missing or incorrect confirmation preserves the complete event" do
    before = event_counts
    [ nil, "", "inne-wydarzenie", @event.title ].each do |confirmation|
      assert_raises(Voting::Invalid) { EventDeletion.call(event: @event, confirmation: confirmation) }
      assert_equal before, event_counts
    end
    assert Event.exists?(@event.id)
  end

  test "a failure at final deletion rolls back removal of related data" do
    before = event_counts
    @event.define_singleton_method(:delete) { raise "Simulated deletion failure" }
    assert_raises(RuntimeError) { EventDeletion.call(event: @event, confirmation: @event.slug) }
    assert_equal before, event_counts
    assert Event.exists?(@event.id)
    assert_equal 25, @event.cells.count
    assert_equal 2, Proposal.where(cell_id: @event.cells.select(:id)).count
  ensure
    @event.singleton_class.remove_method(:delete)
  end

  private

  def event_counts
    [ Event, Option, Vote, Cell, Draw, Proposal, AuditEntry ].map(&:count)
  end
end
