class Vote < ApplicationRecord
  belongs_to :event
  belongs_to :participant
  belongs_to :option
  validates :slot, inclusion: { in: 1..5 }
  def readonly? = persisted?
end
