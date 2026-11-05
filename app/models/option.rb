class Option < ApplicationRecord
  PER_PARTICIPANT_LIMIT = 20

  belongs_to :event
  belongs_to :participant
  belongs_to :merged_into, class_name: "Option", optional: true
  has_many :votes, dependent: :restrict_with_exception
  scope :eligible, -> { where(disqualified_at: nil, merged_into_id: nil) }
  scope :with_votes, -> { where(id: Vote.select(:option_id)) }
  before_validation :normalize_text
  validates :text, presence: true, length: { maximum: 100 }
  validates :normalized_text, uniqueness: { scope: :event_id, message: "taka propozycja już istnieje" }

  private

  def normalize_text
    self.text = text.to_s.unicode_normalize(:nfkc).squish
    self.normalized_text = text.downcase
  end
end
