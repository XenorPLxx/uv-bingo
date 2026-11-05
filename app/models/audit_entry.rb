class AuditEntry < ApplicationRecord
  belongs_to :event
  belongs_to :participant
  def readonly? = persisted?
end
