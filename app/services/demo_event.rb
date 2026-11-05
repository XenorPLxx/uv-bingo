class DemoEvent
  IDEAS = [
    "Nowy zwiastun Wiedźmina IV", "Gabe Newell pojawia się na scenie", "Kolejny remaster gry, którą już mamy",
    "Geoff mówi: World Premiere", "Ktoś dziękuje swojemu kotu", "Zapowiedź gry, która wychodzi jeszcze dziś",
    "Nowe IP od znanego studia", "Zwiastun bez ani sekundy gameplayu", "Silksong dostaje kolejną niespodziankę",
    "Muzyka z gry wywołuje ciarki", "Premiera odległa o co najmniej dwa lata", "Na scenę wchodzi niespodziewany gość",
    "Gra niezależna kradnie całe show", "Ktoś wspomina o Half-Life 3", "Powrót serii zapomnianej od dekady",
    "Ogłoszenie dodatku do ulubionej gry", "W zwiastunie pojawia się smok", "Gra mobilna wygląda jak konsolowa",
    "Znany aktor promuje nową grę", "Publiczność reaguje głośniej niż prowadzący", "Kolejne soulslike z ogromnym bossem",
    "Nagroda trafia do naszego faworyta", "Niespodziewany crossover dwóch serii", "Trailer kończy się bez daty premiery",
    "Nowy horror każe nam zapalić światło", "Widzimy coś z uniwersum Star Wars", "Powrót kanapowego co-opa",
    "Developer odbiera nagrodę w bluzie", "Darmowy weekend ogłoszony na scenie", "Czat jednogłośnie pisze: CINEMA"
  ].freeze

  def self.prepare!
    raise "Demo data is available only in development or staging" unless Rails.env.development? || Rails.env.staging?
    Event.transaction do
      return Event.find_by(slug: "tga-2026-proba") if Event.exists?(slug: "tga-2026-proba")
      event = Event.create!(title: "TGA 2026 — próba generalna", slug: "tga-2026-proba", rehearsal: true,
        description: "Wydarzenie testowe z przykładowymi propozycjami i głosami.",
        opens_at: 1.day.ago, closes_at: 7.days.from_now)
      IDEAS.each_with_index do |text, index|
        voter = Participant.find_or_create_by!(discord_id: "demo-#{index / 5}") { |p| p.display_name = "Gracz przykładowy #{index / 5 + 1}" }
        Voting.cast!(event: event, participant: voter, text: text)
      end
      event
    end
  end
end
