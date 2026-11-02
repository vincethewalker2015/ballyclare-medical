class ClinicalNote < ApplicationRecord
  belongs_to :patient
  belongs_to :encounter
  belongs_to :author, class_name: "StaffMember"

  validates :note_type, :body, presence: true
  validate :associations_match_encounter
  private

  def associations_match_encounter
    return if encounter.blank?

    if patient.present? && patient.id != encounter.patient_id
      errors.add(:patient, "must match the encounter patient")
    end

    if author.present? && author.practice_id != encounter.practice_id
      errors.add(:author, "must belong to the encounter practice")
    end
  end
end
