class OptionMerge
  # The earliest proposal survives so its author keeps the credit.
  def self.call(event:, admin:, option_ids:, reason:)
    event.with_lock do
      raise Voting::Invalid, "Propozycje można łączyć tylko przed losowaniem planszy." if event.draw || event.state != "collecting"
      reason = reason.to_s.strip
      raise Voting::Invalid, "Podaj powód połączenia (od 3 do 200 znaków)." unless reason.length.between?(3, 200)
      options = Array(option_ids).map { |id| event.options.find(id) }
      raise Voting::Invalid, "Wybierz dwie różne propozycje." unless options.size == 2 && options.uniq.size == 2
      target, source = options.sort_by { |option| [ option.created_at, option.id ] }
      raise Voting::Invalid, "Jedna z propozycji została już połączona. Sprawdź aktualną listę." if source.merged_into_id || target.merged_into_id
      raise Voting::Invalid, "Przywróć wykluczone propozycje przed ich połączeniem." if source.disqualified_at || target.disqualified_at

      before = { source: { id: source.id, text: source.text, votes: source.votes.count },
        target: { id: target.id, text: target.text, votes: target.votes.count } }
      duplicates = source.votes.where(participant_id: target.votes.select(:participant_id)).pluck(:id, :participant_id, :slot)
      # Preserve the target vote. Deleting the source duplicate frees its original slot.
      returned = source.votes.where(id: duplicates.map(&:first)).delete_all
      # This administrative operation intentionally bypasses Vote's immutable-record guard.
      transferred = source.votes.update_all(option_id: target.id)
      aliases = event.options.where(merged_into_id: source.id)
      redirected_ids = aliases.pluck(:id)
      aliases.update_all(merged_into_id: target.id, updated_at: Time.current)
      source.update!(merged_into: target, moderation_reason: reason)
      event.audit_entries.create!(participant: admin, action: "merge_options", details: before.merge(
        reason: reason, transferred_votes: transferred, returned_votes: returned,
        refunded_votes: duplicates.map { |id, participant_id, slot| { vote_id: id, participant_id: participant_id, slot: slot } },
        redirected_option_ids: redirected_ids, resulting_votes: target.votes.count))
      event.increment!(:revision)
      { transferred_votes: transferred, returned_votes: returned }
    end
  end
end
