module ApplicationHelper
  DEFAULT_SOCIAL_DESCRIPTION = "Bingo społeczności UV o grach na The Game Awards. Głosowanie na propozycje i plansza aktualizowana na żywo.".freeze

  def social_preview_metadata
    event = @event if controller_path == "events"
    base_url = (ENV["APP_URL"].presence || request.base_url).chomp("/")
    path = event && action_name != "index" ? event_path(event) : root_path
    description = CGI.unescapeHTML(strip_tags(event&.description.to_s)).squish.presence || DEFAULT_SOCIAL_DESCRIPTION

    {
      title: event ? "#{event.title.squish} · TGA Bingo" : "TGA Bingo · UV o grach",
      description: truncate(description, length: 200),
      url: "#{base_url}#{path}",
      image: image_url("uv-space.png", host: base_url)
    }
  end

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
