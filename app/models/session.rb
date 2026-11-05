class Session < ApplicationRecord
  belongs_to :participant
  scope :active, -> { where("expires_at > ?", Time.current) }
end
