class AppointmentHold < ApplicationRecord
  belongs_to :appointment_slot
  belongs_to :patient
end
