class Proposal < ApplicationRecord
  belongs_to :cell
  belongs_to :participant
  validates :mark, inclusion: { in: %w[question cross] }
end
