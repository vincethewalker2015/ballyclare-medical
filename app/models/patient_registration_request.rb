class PatientRegistrationRequest < ApplicationRecord
  REVIEW_STATUSES = %w[awaiting_review verified approved processing completed failed].freeze
  PATIENT_ROUTES = %w[new_patient existing_patient].freeze

  belongs_to :practice
  belongs_to :patient_account
  belongs_to :selected_patient, class_name: "Patient", optional: true
  belongs_to :reviewed_by, class_name: "StaffMember", optional: true
  belongs_to :approved_by, class_name: "StaffMember", optional: true

  validates :patient_account_id, uniqueness: true
  validates :review_status, inclusion: { in: REVIEW_STATUSES }
  validates :patient_route, inclusion: { in: PATIENT_ROUTES }, allow_nil: true
  validate :selected_patient_belongs_to_practice
  validate :reviewers_belong_to_practice

  private

  def selected_patient_belongs_to_practice
    return unless selected_patient && practice
    return if selected_patient.practice_id == practice.id

    errors.add(:selected_patient, "must belong to this practice")
  end

  def reviewers_belong_to_practice
    [ reviewed_by, approved_by ].compact.each do |staff|
      next if staff.active? && staff.practice_id == practice_id && staff.staff_administration_access?
      next if staff.active? && staff.practice.medical_group_id == practice.medical_group_id &&
        (staff.senior_administration_access? ||
         practice.medical_group.chief_of_group_id == staff.user_id)

      errors.add(:base, "reviewers must be active administrators of this practice")
    end
  end
end
