module ApplicationHelper
  def phase_label(phase)
    { "scheduled" => "Głosowanie zaplanowane", "open" => "Głosowanie trwa", "closed" => "Głosowanie zakończone",
      "drawn" => "Plansza gotowa", "live" => "Plansza na żywo", "archived" => "Zakończone" }.fetch(phase)
  end

  def voting_schedule(event)
    "#{event.opens_at.in_time_zone.strftime('%d.%m %H:%M')} – #{event.closes_at.in_time_zone.strftime('%d.%m.%Y %H:%M')}"
  end

  def mark_label(mark)
    { "blank" => "bez oznaczenia", "question" => "? do dyskusji", "cross" => "X potwierdzone" }.fetch(mark)
  end

  def mark_symbol(mark)
    { "blank" => "", "question" => "?", "cross" => "X" }.fetch(mark)
  end
end
