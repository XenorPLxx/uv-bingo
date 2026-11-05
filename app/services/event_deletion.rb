class EventDeletion
  def self.call(event:, confirmation:)
    event.with_lock do
      raise Voting::Invalid, "Wpisz dokładny adres wydarzenia, aby potwierdzić usunięcie." unless confirmation.to_s.strip == event.slug

      # Explicitly remove only this event's data, including immutable draw/audit records.
      Proposal.where(cell_id: Cell.where(event: event).select(:id)).delete_all
      Cell.where(event: event).delete_all
      Draw.where(event: event).delete_all
      Vote.where(event: event).delete_all
      Option.where(event: event).delete_all
      AuditEntry.where(event: event).delete_all
      event.delete
    end
  end
end
