require "test_helper"

class LeaderboardTest < ActiveSupport::TestCase
  setup do
    @event = create_event
    @admin = create_participant
    @ala, @bartek, @celina = %w[Ala Bartek Celina].map { |name| create_participant(display_name: name) }
    @options = seed_options(@event, 25)
    @author_ids = @options.map(&:participant_id)
  end

  def draw_and_mark(*option_indexes, mark: "cross")
    @event.update!(closes_at: 1.second.ago)
    BoardDraw.call(event: @event, admin: @admin)
    @event.update!(state: "live")
    option_indexes.each do |index|
      cell = @event.cells.find_by!(option: @options[index])
      BoardActions.mark!(cell: cell, admin: @admin, mark: mark, revision: cell.revision)
    end
  end

  test "only official X marks score and equal scores share a rank" do
    [ @ala, @bartek ].each { |voter| [ 0, 1 ].each { |index| Voting.cast!(event: @event, participant: voter, option_id: @options[index].id) } }
    Voting.cast!(event: @event, participant: @celina, option_id: @options[0].id)
    Voting.cast!(event: @event, participant: @celina, option_id: @options[2].id)
    draw_and_mark(0, 1)
    draw_question = @event.cells.find_by!(option: @options[2])
    BoardActions.mark!(cell: draw_question, admin: @admin, mark: "question", revision: 0)

    board = Leaderboard.new(@event)
    assert board.any?
    scores = board.predictors.to_h { |entry| [ entry.participant.display_name, [ entry.rank, entry.score ] ] }
    assert_equal [ 1, 2 ], scores.fetch("Ala")
    assert_equal [ 1, 2 ], scores.fetch("Bartek")
    assert_equal [ 3, 1 ], scores.fetch("Celina"), "A question mark does not count as a hit"
    proposers = board.proposers
    assert_equal [ @options[0].text ], proposers.find { |entry| entry.participant.id == @author_ids[0] }.details
    assert_equal [ 1 ], proposers.map(&:score).uniq
  end

  test "no confirmed cells means no rankings" do
    draw_and_mark
    assert_not Leaderboard.new(@event).any?
    assert_empty Leaderboard.new(@event).predictors
  end

  test "the viewer's own entry is appended when it falls outside the top" do
    draw_and_mark(*0..11)
    board = Leaderboard.new(@event)
    # Each seeded option's author voted only for it, so twelve authors tie with one hit.
    assert_equal 12, board.predictors.size
    assert_equal [ 1 ], board.predictors.map(&:rank).uniq
    last = board.predictors.last
    assert_equal board.predictors, board.visible(board.predictors, last.participant), "Tied ranks stay within the top"

    entries = board.predictors.each_with_index.map { |entry, index| entry.with(rank: index + 1) }
    visible = board.visible(entries, entries.last.participant)
    assert_equal 11, visible.size
    assert_equal entries.last, visible.last
    assert_equal 10, board.visible(entries, @ala).size
  end

  test "merged proposals credit the author of the retained proposal" do
    source = Voting.cast!(event: @event, participant: @ala, text: "Duplikat pierwszej zapowiedzi").option
    OptionMerge.call(event: @event, admin: @admin, source_id: source.id, target_id: @options[0].id, reason: "Ta sama zapowiedź")
    draw_and_mark(0)
    proposers = Leaderboard.new(@event).proposers
    assert_equal [ @author_ids[0] ], proposers.map { |entry| entry.participant.id }
    assert_includes Leaderboard.new(@event).predictors.map(&:participant), @ala, "Ala's vote moved to the retained proposal"
  end
end
