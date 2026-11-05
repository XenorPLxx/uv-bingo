class Voting
  class Invalid < StandardError; end

  def self.cast!(event:, participant:, option_id: nil, text: nil)
    vote = event.with_lock do
      participant.with_lock do
        raise Invalid, "Głosowanie jest zamknięte." unless event.voting_open?
        if option_id
          option = event.options.find_by(id: option_id)
          raise Invalid, "Ta propozycja nie jest już dostępna do głosowania." unless option
          option = option.merged_into if option.merged_into_id
          raise Invalid, "Ta propozycja nie jest już dostępna do głosowania." unless option && !option.disqualified_at && !option.merged_into_id
          existing = participant.votes.find_by(option: option)
          return existing if existing
        end
        available_slot = ((1..5).to_a - participant.votes.where(event: event).pluck(:slot)).first
        raise Invalid, "Wykorzystano wszystkie 5 głosów. Cofnij jeden, aby wybrać inną propozycję." unless available_slot
        unless option
          if event.options.where(participant: participant).count >= Option::PER_PARTICIPANT_LIMIT
            raise Invalid, "Możesz dodać maksymalnie #{Option::PER_PARTICIPANT_LIMIT} propozycji na wydarzenie. Nadal możesz głosować na istniejące propozycje."
          end
          option = event.options.create!(participant: participant, text: text)
        end
        vote = Vote.create!(event: event, participant: participant, option: option, slot: available_slot)
        event.increment!(:revision)
        vote
      end
    end
    notify(event)
    vote
  end

  def self.withdraw!(event:, participant:, vote_id:)
    vote = event.with_lock do
      participant.with_lock do
        raise Invalid, "Głosowanie jest zamknięte." unless event.voting_open?
        # Votes remain immutable; only this window-checked operation removes a row.
        vote = participant.votes.where(event: event).find(vote_id).delete
        event.increment!(:revision)
        vote
      end
    end
    notify(event)
    vote
  end

  # Viewers refetch on notification, so it must follow the commit that changed the totals.
  def self.notify(event)
    ActiveRecord.after_all_transactions_commit { event.broadcast_update! }
  end
  private_class_method :notify
end
