module SummaryHelper
  MONTHS = %w[stycznia lutego marca kwietnia maja czerwca lipca sierpnia września października listopada grudnia].freeze
  WEEKS = { 7 => "Tydzień", 14 => "Dwa tygodnie", 21 => "Trzy tygodnie", 28 => "Cztery tygodnie" }.freeze

  def long_date(date) = "#{date.day} #{MONTHS[date.month - 1]}"
  def long_time(time) = "#{long_date(time.in_time_zone)}, #{time.in_time_zone.strftime('%H:%M')}"

  # "17–23 listopada" or "28 listopada – 2 grudnia".
  def date_span(first, last)
    return long_date(first) if first >= last
    first.month == last.month ? "#{first.day}–#{long_date(last)}" : "#{long_date(first)} – #{long_date(last)}"
  end

  def voting_duration(days) = WEEKS.fetch(days) { count_label(days, "dzień", "dni", "dni") }

  def time_left_label(value, unit)
    unit == :days ? count_form(value, "dzień", "dni", "dni") : count_form(value, "godzina", "godziny", "godzin")
  end
end
