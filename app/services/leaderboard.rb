# Rankings for a drawn board. Only official X marks count as hits.
class Leaderboard
  Entry = Data.define(:participant, :score, :rank, :details)
  TOP = 10

  def initialize(event)
    @event = event
    @hit_option_ids = event.cells.where(mark: "cross").pluck(:option_id)
  end

  def any? = @hit_option_ids.any?

  # Participants by how many of their votes landed on confirmed cells.
  def predictors
    @predictors ||= rank(Vote.where(event: @event, option_id: @hit_option_ids).group(:participant_id).count)
  end

  # Authors by how many of their proposals were confirmed. Merged sources stay credited to the retained proposal's author.
  def proposers
    @proposers ||= begin
      hits = @event.options.where(id: @hit_option_ids).order(:created_at, :id).group_by(&:participant_id)
      rank(hits.transform_values(&:size), details: hits.transform_values { |options| options.map(&:text) })
    end
  end

  # The top entries, plus the viewer's own entry when it falls outside them.
  def visible(entries, participant)
    top = entries.select { |entry| entry.rank <= TOP }
    own = entries.find { |entry| entry.participant == participant }
    own && !top.include?(own) ? top + [ own ] : top
  end

  private

  def rank(scores, details: {})
    participants = Participant.where(id: scores.keys).index_by(&:id)
    sorted = scores.sort_by { |id, score| [ -score, participants.fetch(id).display_name.downcase, id ] }
    previous = nil
    sorted.each_with_index.map do |(id, score), index|
      # Equal scores share a rank (1, 1, 3).
      rank = previous&.score == score ? previous.rank : index + 1
      previous = Entry.new(participant: participants.fetch(id), score: score, rank: rank, details: details.fetch(id, []))
    end
  end
end
