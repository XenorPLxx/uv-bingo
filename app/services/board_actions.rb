class BoardActions
  def self.propose!(cell:, participant:, mark:, revision:)
    cell.event.with_lock do
      cell.reload
      raise Voting::Invalid, "Propozycje są dostępne podczas transmisji." unless cell.event.state == "live"
      raise Voting::Invalid, "Pole zostało zmienione. Sprawdź aktualną planszę." unless cell.revision == revision.to_i
      proposal = cell.proposals.find_or_initialize_by(participant: participant, revision: cell.revision)
      if mark == "blank"
        proposal.destroy! if proposal.persisted?
      else
        proposal.update!(mark: mark)
      end
      cell.event.increment!(:revision)
    end
  end

  def self.mark!(cell:, admin:, mark:, revision:)
    cell.event.with_lock do
      cell.reload
      raise Voting::Invalid, "Oznaczanie pól jest dostępne podczas transmisji." unless cell.event.state == "live"
      raise Voting::Invalid, "Inny admin zmienił to pole. Odśwież planszę." unless cell.revision == revision.to_i
      before = cell.mark
      cell.update!(mark: mark, revision: cell.revision + 1)
      cell.event.audit_entries.create!(participant: admin, action: "mark",
        details: { position: cell.position, before: before, after: mark, revision: cell.revision })
      cell.event.increment!(:revision)
    end
  end
end
