class Cell < ApplicationRecord
  MARKS = %w[blank question cross].freeze
  belongs_to :event
  belongs_to :option
  has_many :proposals, dependent: :restrict_with_exception
  validates :mark, inclusion: { in: MARKS }

  def current_proposals
    proposals.select { |proposal| proposal.revision == revision }
  end
end
