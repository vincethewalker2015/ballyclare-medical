class AuditEvent < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :practice

  belongs_to :auditable, polymorphic: true

  validates :action, presence: true
end
