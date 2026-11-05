module AuditHelper
  SETTING_NAMES = { "title" => "tytuł", "description" => "opis", "opens_at" => "początek głosowania", "closes_at" => "koniec głosowania" }.freeze

  # One readable line per admin action. Noun phrases avoid guessing the admin's grammatical gender.
  def audit_summary(entry)
    details = entry.details
    case entry.action
    when "create_event" then "Utworzenie wydarzenia"
    when "draw" then "Losowanie planszy"
    when "transition" then { "live" => "Start transmisji", "archived" => "Zakończenie wydarzenia" }.fetch(details["after"], "Zmiana etapu")
    when "settings"
      changed = SETTING_NAMES.select { |key, _| details.dig("before", key) != details.dig("after", key) }.values
      [ "Zmiana ustawień", changed.join(", ").presence ].compact.join(": ")
    when "mark"
      after = details["after"]
      "Pole #{details['position'].to_i + 1}: #{after == 'blank' ? 'wyczyszczone' : mark_label(after)}"
    when "moderate" then moderation_summary(details)
    when "merge_options"
      with_reason("Połączenie: „#{details.dig('source', 'text')}” → „#{details.dig('target', 'text')}”", details["reason"])
    else entry.action
    end
  end

  private

  def moderation_summary(details)
    before, after = details.values_at("before", "after").map { |state| state || {} }
    summary = if before["disqualified_at"].nil? && after["disqualified_at"] then "Wykluczenie: „#{after['text']}”"
    elsif before["disqualified_at"] && after["disqualified_at"].nil? then "Przywrócenie: „#{after['text']}”"
    elsif before["text"] != after["text"] then "Korekta: „#{before['text']}” → „#{after['text']}”"
    else "Moderacja: „#{after['text']}”"
    end
    with_reason(summary, details["reason"])
  end

  def with_reason(summary, reason)
    reason.present? ? "#{summary} (#{reason})" : summary
  end
end
