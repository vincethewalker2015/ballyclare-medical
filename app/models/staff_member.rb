class StaffMember < ApplicationRecord
  belongs_to :practice
  belongs_to :user
end
