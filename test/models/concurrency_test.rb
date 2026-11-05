require "test_helper"

class ConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  teardown do
    [ Proposal, Cell, Draw, AuditEntry, Vote, Option, LoginToken, Session, Participant, Event ].each(&:delete_all)
  end

  test "simultaneous requests can consume only the slot freed by withdrawal" do
    event = create_event
    voter = create_participant
    votes = 5.times.map { |i| Voting.cast!(event: event, participant: voter, text: "Mój #{i}") }
    Voting.withdraw!(event: event, participant: voter, vote_id: votes.fetch(1).id)
    options = seed_options(event, 3)
    gate = Queue.new
    threads = options.map do |option|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          Voting.cast!(event: Event.find(event.id), participant: Participant.find(voter.id), option_id: option.id)
          :accepted
        rescue Voting::Invalid
          :rejected
        end
      end
    end
    3.times { gate << true }
    assert_equal [ :accepted, :rejected, :rejected ], threads.map(&:value).sort
    assert_equal 5, voter.votes.count
    assert_equal [ 1, 2, 3, 4, 5 ], voter.votes.order(:slot).pluck(:slot)
  end

  test "concurrent proposal submissions cannot exceed the twenty proposal cap" do
    event = create_event
    voter = create_participant
    19.times { |i| event.options.create!(participant: voter, text: "Wcześniejsza propozycja #{i}") }
    gate = Queue.new
    threads = 2.times.map do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          Voting.cast!(event: Event.find(event.id), participant: Participant.find(voter.id), text: "Równoczesna propozycja #{i}")
          :accepted
        rescue Voting::Invalid
          :rejected
        end
      end
    end
    2.times { gate << true }
    assert_equal [ :accepted, :rejected ], threads.map(&:value).sort
    assert_equal 20, event.options.where(participant: voter).count
    assert_equal 1, voter.votes.where(event: event).count
  end

  test "merge and a simultaneous cached vote cannot double count a participant" do
    event = create_event
    admin = create_participant
    voter = create_participant
    source, target = seed_options(event, 2)
    Voting.cast!(event: event, participant: voter, option_id: source.id)
    Voting.cast!(event: event, participant: voter, option_id: target.id)
    gate = Queue.new
    operations = [
      -> { OptionMerge.call(event: Event.find(event.id), admin: admin, source_id: source.id, target_id: target.id, reason: "Duplikat") },
      -> { Voting.cast!(event: Event.find(event.id), participant: Participant.find(voter.id), option_id: source.id) }
    ]
    threads = operations.map do |operation|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          operation.call
        end
      end
    end
    2.times { gate << true }
    threads.each(&:value)
    assert_equal 1, voter.votes.where(event: event).count
    assert_equal target.id, voter.votes.first.option_id
    assert_equal 4, voter.votes_remaining(event)
    assert_equal 1, event.audit_entries.where(action: "merge_options").count
  end

  test "simultaneous repeated merges refund each duplicate only once" do
    event = create_event
    admin = create_participant
    voter = create_participant
    source, target = seed_options(event, 2)
    Voting.cast!(event: event, participant: voter, option_id: source.id)
    Voting.cast!(event: event, participant: voter, option_id: target.id)
    gate = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          OptionMerge.call(event: Event.find(event.id), admin: admin, source_id: source.id, target_id: target.id, reason: "Duplikat")
          :merged
        rescue Voting::Invalid
          :rejected
        end
      end
    end
    2.times { gate << true }
    assert_equal [ :merged, :rejected ], threads.map(&:value).sort
    assert_equal 1, voter.votes.count
    assert_equal 4, voter.votes_remaining(event)
    assert_equal 1, event.audit_entries.where(action: "merge_options").count
  end

  test "simultaneous draw requests produce one board and one audit record" do
    event = create_event
    admin = create_participant
    seed_options(event, 25)
    event.update!(closes_at: 1.second.ago)
    gate = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          BoardDraw.call(event: Event.find(event.id), admin: admin).id
        end
      end
    end
    2.times { gate << true }
    assert_equal 1, threads.map(&:value).uniq.size
    assert_equal 25, event.cells.count
    assert_equal 1, event.audit_entries.where(action: "draw").count
  end
end
