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
        available_slot = ((1..5).to_a - participant.votes.where(event: event).pluck(:slot)).first
        raise Invalid, "Wykorzystano wszystkie 5 głosów. Cofnij jeden, aby wybrać inną propozycję." unless available_slot
        option ||= event.options.create!(participant: participant, text: text)
        Vote.create!(event: event, participant: participant, option: option, slot: available_slot)
      end
    end
  end

  def self.withdraw!(event:, participant:, vote_id:)
    event.with_lock do
      participant.with_lock do
        raise Invalid, "Głosowanie jest zamknięte." unless event.voting_open?
        # Votes remain immutable; only this window-checked operation removes a row.
        participant.votes.where(event: event).find(vote_id).delete
      end
    end
  end
end
