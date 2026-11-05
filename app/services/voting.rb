class Voting
  class Invalid < StandardError; end

  def self.cast!(event:, participant:, option_id: nil, text: nil)
    event.with_lock do
      participant.with_lock do
        raise Invalid, "Głosowanie jest zamknięte." unless event.voting_open?
        if option_id
          option = event.options.eligible.find(option_id)
          existing = participant.votes.find_by(option: option)
          return existing if existing
        end
        used = participant.votes.where(event: event).count
        raise Invalid, "Wykorzystano wszystkie 5 głosów." if used >= 5
        option ||= event.options.create!(participant: participant, text: text)
        Vote.create!(event: event, participant: participant, option: option, slot: used + 1)
      end
    end
  end
end
