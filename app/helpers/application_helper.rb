module ApplicationHelper
  def phase_label(phase)
    { "scheduled" => "Start już wkrótce", "open" => "Głosowanie trwa", "closed" => "Głosowanie zakończone",
      "drawn" => "Plansza gotowa", "live" => "Gramy na żywo", "archived" => "Zakończone" }.fetch(phase)
  end

  def voting_schedule(event)
    "#{event.opens_at.in_time_zone.strftime('%d.%m %H:%M')} – #{event.closes_at.in_time_zone.strftime('%d.%m.%Y %H:%M')} · Warszawa"
  end

  def mark_label(mark)
    { "blank" => "bez oznaczenia", "question" => "? do dyskusji", "cross" => "X potwierdzone" }.fetch(mark)
  end

  def mark_symbol(mark)
    { "blank" => "", "question" => "?", "cross" => "X" }.fetch(mark)
  end
end
