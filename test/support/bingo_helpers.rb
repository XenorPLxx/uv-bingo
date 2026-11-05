module BingoHelpers
  def create_event(**attributes)
    Event.create!({ title: "TGA Test", slug: "test-#{SecureRandom.hex(5)}", opens_at: 1.hour.ago.change(usec: 0), closes_at: 1.day.from_now.change(usec: 0) }.merge(attributes))
  end

  def create_participant(**attributes)
    Participant.create!({ discord_id: SecureRandom.random_number(10**18).to_s, display_name: "Gracz" }.merge(attributes))
  end

  def seed_options(event, count = 30)
    count.times.map do |index|
      voter = create_participant
      Voting.cast!(event: event, participant: voter, text: "Zapowiedź numer #{index + 1}").option
    end
  end

  def with_env(**values)
    previous = values.to_h { |key, _| [ key.to_s, ENV[key.to_s] ] }
    values.each { |key, value| ENV[key.to_s] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  def sign_in_as(participant)
    token = LoginToken.issue!(participant: participant, interaction_id: SecureRandom.uuid)
    get "/login", params: { token: token }
    post "/login/confirm"
    assert_response :redirect
  end
end
