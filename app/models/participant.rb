class Participant < ApplicationRecord
  has_many :votes, dependent: :restrict_with_exception
  has_many :options, dependent: :restrict_with_exception
  has_many :sessions, dependent: :destroy
  has_many :login_tokens, dependent: :destroy
  # create_or_find_by! relies on the unique database index, including concurrent logins.
  validates :discord_id, presence: true
  validates :display_name, presence: true, length: { maximum: 80 }

  def admin?
    ENV.fetch("ADMIN_DISCORD_IDS", "").split(",").map(&:strip).include?(discord_id)
  end

  def votes_remaining(event)
    5 - votes.where(event: event).count
  end
end
