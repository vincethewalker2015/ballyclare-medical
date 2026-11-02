class ClinicalNote < ApplicationRecord
  belongs_to :patient
  belongs_to :encounter
  belongs_to :author, class_name: "StaffMember"

  validates :note_type, presence: true
  validates :status, inclusion: { in: %w[draft signed] }
  validates :body, presence: true, unless: :draft?
  validate :signed_note_immutable, on: :update

  def draft?
    status == "draft"
  end

  def signed_note_immutable
    errors.add(:base, "Signed clinical notes cannot be edited") if status_in_database == "signed"
  end
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
