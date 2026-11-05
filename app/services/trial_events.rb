class TrialEvents
  VOTING_SLUG = "proba-glosowania".freeze
  BOARD_SLUG = "plansza-testowa".freeze

  def self.prepare!
    Event.transaction do
      setup = Participant.find_or_create_by!(discord_id: "trial-setup") { |person| person.display_name = "Konfiguracja próby" }
      board = Event.find_by(slug: BOARD_SLUG) || prepare_board(setup)
      voting = Event.find_by(slug: VOTING_SLUG) || prepare_voting
      [ voting, board ]
    end
  end

  def self.prepare_voting
    event = Event.create!(title: "TGA 2026 — próba głosowania", slug: VOTING_SLUG, rehearsal: true,
      description: "Przykładowe propozycje do przetestowania głosowania. Możesz dodawać własne i zmieniać głosy do końca próby.",
      opens_at: 1.minute.ago, closes_at: 7.days.from_now)
    DemoEvent::IDEAS.each_with_index do |text, index|
      author = participant("voting-#{index / 15}", "Przykładowe propozycje #{index / 15 + 1}")
      event.options.create!(participant: author, text: text)
    end
    event
  end

  def self.prepare_board(setup)
    event = Event.create!(title: "Plansza testowa — oznaczanie pól", slug: BOARD_SLUG, rehearsal: true,
      description: "Przykładowa plansza do testowania sugestii ? i X oraz oznaczeń administracji.",
      opens_at: 1.day.ago, closes_at: 1.hour.from_now)
    DemoEvent::IDEAS.first(25).each_with_index do |text, index|
      voter = participant("board-#{index / 5}", "Przykładowy uczestnik #{index / 5 + 1}")
      Voting.cast!(event: event, participant: voter, text: text)
    end
    event.update!(closes_at: 1.second.ago)
    BoardDraw.call(event: event, admin: setup)
    event.audit_entries.create!(participant: setup, action: "transition", details: { before: "collecting", after: "live", source: "trial_setup" })
    event.update!(state: "live", revision: event.revision + 1)
    event
  end

  def self.participant(suffix, name)
    Participant.find_or_create_by!(discord_id: "trial-#{suffix}") { |person| person.display_name = name }
  end

  private_class_method :prepare_voting, :prepare_board, :participant
end
