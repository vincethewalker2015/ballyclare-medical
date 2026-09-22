class PatientIdentifier < ApplicationRecord
  belongs_to :patient

  validates :identifier_type, :identifier_value, presence: true

  validates :identifier_value,
    uniqueness: { scope: [ :patient_id, :identifier_type ] }
end
