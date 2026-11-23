# Voting snapshot for the shareable admin summary card.
class EventSummary
  BOARD_SIZE = 25
  CENTER = 12
  AUTHORS = 10
  Tile = Data.define(:option, :votes, :place)
  Author = Data.define(:name, :count)

  attr_reader :event

  def initialize(event)
    @event = event
    @counts = event.votes.group(:option_id).count
    @eligible = event.options.eligible.includes(:participant).to_a
  end

  def votes_count = @counts.values.sum
  def voters_count = @voters_count ||= event.votes.distinct.count(:participant_id)
  def proposals_count = @eligible.size

  # Eligible proposals with votes in public display order, capped at the board size.
  def ranked
    @ranked ||= @eligible.select { |option| @counts.key?(option.id) }
      .sort_by { |option| [ -@counts[option.id], option.created_at, option.id ] }
      .first(BOARD_SIZE).each_with_index.map { |option, index| Tile.new(option:, votes: @counts[option.id], place: index + 1) }
  end

  def leader = ranked.first
  def leader_tied? = ranked.size > 1 && ranked[1].votes == leader.votes
  def missing = BOARD_SIZE - ranked.size

  # The leader takes the center, the rest fill row by row; nil is a free field.
  # The real draw shuffles everything except the center.
  def board
    rest = ranked.drop(1)
    Array.new(BOARD_SIZE) { |position| position == CENTER ? leader : rest.shift }
  end

  # 0–4 relative to the leader, for tile shading.
  def heat(tile)
    top = leader.votes
    top > 1 ? ((tile.votes - 1) * 4.0 / (top - 1)).round : 0
  end

  def authors
    @eligible.group_by(&:participant)
      .map { |participant, options| Author.new(name: participant.display_name, count: options.size) }
      .sort_by { |author| [ -author.count, author.name.downcase ] }.first(AUTHORS)
  end

  # Calendar days of voting so far in the app time zone, counting the opening day.
  def first_day = event.opens_at.in_time_zone.to_date
  def last_day = [ Time.current, event.closes_at ].min.in_time_zone.to_date
  def voting_days = [ (last_day - first_day).to_i + 1, 0 ].max

  # Whole calendar days until closing, or hours on the closing day.
  def time_left
    days = (event.closes_at.in_time_zone.to_date - Date.current).to_i
    days.positive? ? [ days, :days ] : [ ((event.closes_at - Time.current) / 1.hour).ceil, :hours ]
  end
end
