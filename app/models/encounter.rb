class Encounter < ApplicationRecord
  belongs_to :practice
  belongs_to :patient
  belongs_to :appointment, optional: true
  belongs_to :clinician, class_name: "StaffMember"

  has_many :clinical_notes, dependent: :restrict_with_error

  validates :encounter_type, :started_at, presence: true

  validate :ends_after_start
  validate :associations_belong_to_practice

  private

  def associations_belong_to_practice
    return if practice.blank?

    if patient.present? && patient.practice_id != practice.id
      errors.add(:patient, "must belong to the encounter practice")
    end

    if clinician.present? && clinician.practice_id != practice.id
      errors.add(:clinician, "must belong to the encounter practice")
    end

    if appointment.present? && appointment.practice_id != practice.id
      errors.add(:appointment, "must belong to the encounter practice")
    end

    if appointment.present? && patient.present? && appointment.patient_id != patient.id
      errors.add(:appointment, "must belong to the encounter patient")
    end

    if appointment.present? && clinician.present? && appointment.clinician_id != clinician.id
      errors.add(:appointment, "must belong to the encounter clinician")
    end
  end

  def ends_after_start
    return if started_at.blank? || ended_at.blank?

    errors.add(:ended_at, "must not be before started_at") if ended_at < started_at
  end
end
