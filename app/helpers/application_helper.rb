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

  # Why the current viewer cannot add a proposal; relies on EventsController#prepare_voting.
  def add_option_unavailable_message
    if !current_participant
      "Zaloguj się, aby dodać propozycję."
    elsif @authored_option_count >= Option::PER_PARTICIPANT_LIMIT
      "Osiągnięto limit #{Option::PER_PARTICIPANT_LIMIT} propozycji. Nadal możesz głosować na istniejące propozycje."
    elsif @remaining.zero? && @event.voting_open?
      "Wykorzystano 5 głosów. Cofnij jeden, aby dodać propozycję."
    else
      "Dodawanie propozycji jest dostępne w czasie głosowania."
    end
  end

  # Polish count forms: 1 głos, 2–4 głosy (except 12–14), otherwise głosów.
  def count_label(count, one, few, many)
    form = if count == 1 then one
    elsif (2..4).cover?(count % 10) && !(12..14).cover?(count % 100) then few
    else many
    end
    "#{count} #{form}"
  end

  def votes_label(count) = count_label(count, "głos", "głosy", "głosów")

  def admin_time(time)
    time ? time.in_time_zone.strftime("%d.%m.%Y %H:%M") : "—"
  end

  def option_status_tag(option)
    label = if option.merged_into_id then "POŁĄCZONA"
    elsif option.disqualified_at then "WYKLUCZONA"
    end
    tag.span(label, class: "tag status-tag") if label
  end

  def mark_label(mark)
    { "blank" => "bez oznaczenia", "question" => "? do dyskusji", "cross" => "X potwierdzone" }.fetch(mark)
  end

  def mark_symbol(mark)
    { "blank" => "", "question" => "?", "cross" => "X" }.fetch(mark)
  end
end
