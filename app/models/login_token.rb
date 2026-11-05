class LoginToken < ApplicationRecord
  belongs_to :participant
  scope :usable, -> { where(consumed_at: nil).where("expires_at > ?", Time.current) }

  def self.issue!(participant:, interaction_id:)
    raw = SecureRandom.urlsafe_base64(32)
    create!(participant: participant, interaction_id: interaction_id,
      token_digest: Digest::SHA256.hexdigest(raw), expires_at: 10.minutes.from_now)
    raw
  end

  def self.find_usable(raw)
    usable.find_by(token_digest: Digest::SHA256.hexdigest(raw.to_s))
  end
end
