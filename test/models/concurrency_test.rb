require "test_helper"

class ConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  teardown do
    [ Proposal, Cell, Draw, AuditEntry, Vote, Option, LoginToken, Session, Participant, Event ].each(&:delete_all)
  end

  test "simultaneous Discord sign-ins share one account and each receive a private link" do
    key = Ed25519::SigningKey.generate
    gate = Queue.new
    with_env DISCORD_PUBLIC_KEY: key.verify_key.to_bytes.unpack1("H*"), DISCORD_GUILD_ID: "guild-123", APP_URL: "https://bingo.example" do
      threads = 2.times.map do |attempt|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            gate.pop
            timestamp = Time.now.to_i.to_s
            body = JSON.generate(id: "concurrent-login-#{attempt}", type: 2, guild_id: "guild-123", data: { name: "bingo" },
              member: { user: { id: "same-discord-user", username: "Tester" } })
            client = ActionDispatch::Integration::Session.new(Rails.application)
            client.post "/discord/interactions", params: body, headers: { "CONTENT_TYPE" => "application/json",
              "X-Signature-Ed25519" => key.sign(timestamp + body).unpack1("H*"), "X-Signature-Timestamp" => timestamp }
            [ client.response.status, client.response.parsed_body.dig("data", "flags") ]
          end
        end
      end
      2.times { gate << true }
      assert_equal [ [ 200, 64 ], [ 200, 64 ] ], threads.map(&:value)
    end
    participant = Participant.find_by!(discord_id: "same-discord-user")
    assert_equal 1, Participant.where(discord_id: participant.discord_id).count
    assert_equal [ participant.id, participant.id ], LoginToken.order(:id).pluck(:participant_id)
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
