class AppointmentSlot < ApplicationRecord
  belongs_to :practice
  belongs_to :availability_block
end
