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

  def possible_existing_patients
    Patient.possible_existing_for(
      practice: practice, first_name: first_name, last_name: last_name,
      date_of_birth: date_of_birth
    )
  end

  private

  def selected_patient_belongs_to_practice
    return unless selected_patient && practice
    return if selected_patient.practice_id == practice.id

    errors.add(:selected_patient, "must belong to this practice")
  end

  def reviewers_belong_to_practice
    { reviewed_by: reviewed_by, approved_by: approved_by }.each do |role, staff|
      next unless staff
      # Historical review and approval records remain valid after a role change.
      # Newly assigned reviewers and approvers must still hold current authority.
      next if persisted? && !will_save_change_to_attribute?("#{role}_id")
      next if staff.active? && staff.practice_id == practice_id && staff.staff_administration_access?
      next if staff.active? && staff.practice.medical_group_id == practice.medical_group_id &&
        (staff.senior_administration_access? ||
         practice.medical_group.chief_of_group_id == staff.user_id)

      errors.add(:base, "reviewers and approvers must have active administrative authority")
    end
  end
end
