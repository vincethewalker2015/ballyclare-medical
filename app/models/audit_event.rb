class AuditEvent < ApplicationRecord
  belongs_to :user
  belongs_to :practice
end
