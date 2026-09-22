class ClinicalNote < ApplicationRecord
  belongs_to :patient
  belongs_to :encounter
end
