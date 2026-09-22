class Appointment < ApplicationRecord
  belongs_to :practice
  belongs_to :appointment_slot
  belongs_to :patient
end
