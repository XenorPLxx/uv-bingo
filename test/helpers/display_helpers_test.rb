require "test_helper"

class DisplayHelpersTest < ActionView::TestCase
  include ApplicationHelper
  include AuditHelper

  test "Polish vote counts use the right plural form" do
    expected = { 0 => "0 głosów", 1 => "1 głos", 2 => "2 głosy", 4 => "4 głosy", 5 => "5 głosów", 11 => "11 głosów",
      12 => "12 głosów", 14 => "14 głosów", 21 => "21 głosów", 22 => "22 głosy", 104 => "104 głosy", 112 => "112 głosów" }
    expected.each { |count, label| assert_equal label, votes_label(count) }
    assert_equal "3 trafienia", count_label(3, "trafienie", "trafienia", "trafień")
  end

  test "admin history reads as Polish summaries" do
    entry = ->(action, details) { AuditEntry.new(action: action, details: details) }
    assert_equal "Pole 7: X potwierdzone", audit_summary(entry.("mark", { "position" => 6, "before" => "blank", "after" => "cross" }))
    assert_equal "Pole 1: wyczyszczone", audit_summary(entry.("mark", { "position" => 0, "before" => "question", "after" => "blank" }))
    assert_equal "Start transmisji", audit_summary(entry.("transition", { "before" => "collecting", "after" => "live" }))
    assert_equal "Zmiana ustawień: tytuł, koniec głosowania", audit_summary(entry.("settings", {
      "before" => { "title" => "A", "description" => nil, "opens_at" => "1", "closes_at" => "2" },
      "after" => { "title" => "B", "description" => nil, "opens_at" => "1", "closes_at" => "3" } }))
    assert_equal "Wykluczenie: „Pomysł” (spam)", audit_summary(entry.("moderate", {
      "before" => { "text" => "Pomysł", "disqualified_at" => nil }, "after" => { "text" => "Pomysł", "disqualified_at" => "2026-11-05" }, "reason" => "spam" }))
    assert_equal "Korekta: „Pomysl” → „Pomysł” (literówka)", audit_summary(entry.("moderate", {
      "before" => { "text" => "Pomysl", "disqualified_at" => nil }, "after" => { "text" => "Pomysł", "disqualified_at" => nil }, "reason" => "literówka" }))
    assert_equal "Połączenie: „A” → „B” (duplikat)", audit_summary(entry.("merge_options", {
      "source" => { "text" => "A" }, "target" => { "text" => "B" }, "reason" => "duplikat" }))
    assert_equal "Losowanie planszy", audit_summary(entry.("draw", {}))
  end
end
