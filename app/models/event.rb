class Event < ApplicationRecord
  has_many :options, dependent: :restrict_with_exception
  has_many :votes, dependent: :restrict_with_exception
  has_many :cells, -> { order(:position) }, dependent: :restrict_with_exception
  has_many :audit_entries, dependent: :restrict_with_exception
  has_one :draw, dependent: :restrict_with_exception
  validates :title, presence: true, length: { maximum: 100 }
  validates :description, length: { maximum: 1000 }
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :opens_at, :closes_at, presence: true
  validates :state, inclusion: { in: %w[collecting live archived] }
  validate :valid_window

  def to_param = slug

  def voting_open?(at: Time.current)
    state == "collecting" && opens_at <= at && at < closes_at && !draw
  end

  def phase
    return state if %w[live archived].include?(state)
    return "drawn" if draw
    return "scheduled" if Time.current < opens_at
    return "closed" if Time.current >= closes_at
    "open"
  end

  def broadcast_update!
    ActionCable.server.broadcast("event:#{id}", { revision: revision })
  rescue StandardError => error
    Rails.logger.error("Board broadcast failed: #{error.class}")
    # The client's periodic resync repairs a missed notification after a committed write.
  end

  def completed_lines
    marked = cells.select { |cell| cell.mark == "cross" }.map(&:position)
    lines = 5.times.map { |r| 5.times.map { |c| r * 5 + c } }
    lines += 5.times.map { |c| 5.times.map { |r| r * 5 + c } }
    lines += [ [ 0, 6, 12, 18, 24 ], [ 4, 8, 12, 16, 20 ] ]
    lines.select { |line| (line - marked).empty? }
  end

  private

  def valid_window
    errors.add(:closes_at, "musi być później niż początek") if opens_at && closes_at && closes_at <= opens_at
  end
end
