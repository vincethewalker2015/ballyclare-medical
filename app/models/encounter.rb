class Encounter < ApplicationRecord
  belongs_to :practice
  belongs_to :patient
  belongs_to :appointment
end
