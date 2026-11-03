class PatientAccountLink < ApplicationRecord
  STATUSES = %w[pending approved revoked].freeze
  VERIFICATION_METHODS = %w[in_person approved_remote].freeze

  belongs_to :practice
  belongs_to :patient
  belongs_to :patient_account
  belongs_to :verified_by, class_name: "StaffMember", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :patient_id, uniqueness: true
  validates :patient_account_id, uniqueness: true
  validates :verification_method, inclusion: { in: VERIFICATION_METHODS }, allow_nil: true
  validates :verification_method, :verified_at, :verified_by, :approved_at,
    presence: true, if: :approved?
  validate :patient_belongs_to_practice
  validate :verifier_belongs_to_practice
  validate :account_is_confirmed_before_approval
  validate :approved_link_cannot_be_reassigned, on: :update

  scope :approved, -> { where(status: "approved") }

  after_create_commit :refresh_portal_on_first_approval, if: :approved?
  after_update_commit :refresh_documents_when_revoked, if: :saved_change_to_status?

  def refresh_portal_on_first_approval
    Turbo::StreamsChannel.broadcast_refresh_to(patient_account, :portal_access)
  end

  def refresh_documents_when_revoked
    Turbo::StreamsChannel.broadcast_refresh_to(self, :clinical_documents) if status == "revoked"
    Turbo::StreamsChannel.broadcast_refresh_to(patient_account, :portal_access) if status.in?(%w[approved revoked])
  end

  def approved?
    status == "approved"
  end

  private

  def patient_belongs_to_practice
    return if patient.nil? || practice.nil? || patient.practice_id == practice.id

    errors.add(:patient, "must belong to the same practice")
  end

  def verifier_belongs_to_practice
    # Preserve historical verification when authority changes after approval.
    # Recheck authority when a verifier is assigned or the link is approved.
    return if persisted? && !will_save_change_to_verified_by_id? &&
      !will_save_change_to_status?(to: "approved")
    return if verified_by.nil? || practice.nil?
    # A registration's recorded identity check remains historical evidence even
    # if its reviewer has since left. Only trust an already-approved request,
    # and require its approver to retain current group authority.
    return if new_record? && approved? && historical_registration_verification?
    return if verified_by.active? && verified_by.practice_id == practice.id &&
      verified_by.staff_administration_access?
    return if verified_by.active? &&
      verified_by.practice.medical_group_id == practice.medical_group_id &&
      (verified_by.senior_administration_access? ||
       practice.medical_group.chief_of_group_id == verified_by.user_id)

    errors.add(:verified_by, "must be an active practice administrator")
  end


  def historical_registration_verification?
    request_record = PatientRegistrationRequest.find_by(
      practice_id: practice.id,
      patient_account_id: patient_account_id,
      reviewed_by_id: verified_by_id,
      verification_method: verification_method,
      identity_verified_at: verified_at,
      approved_at: approved_at,
      review_status: %w[approved processing]
    )
    return false unless request_record
    return false unless request_record.patient_route == "new_patient" ||
      (request_record.patient_route == "existing_patient" &&
       request_record.selected_patient_id == patient_id)

    approver = request_record.approved_by
    approver&.active? &&
      approver.practice.medical_group_id == practice.medical_group_id &&
      (approver.senior_administration_access? ||
       practice.medical_group.chief_of_group_id == approver.user_id)
  end

  def account_is_confirmed_before_approval
    return unless approved? && patient_account && !patient_account.confirmed?

    errors.add(:patient_account, "must have a confirmed email address")
  end

  def approved_link_cannot_be_reassigned
    return unless status_in_database == "approved"
    return unless will_save_change_to_patient_id? ||
      will_save_change_to_patient_account_id? || will_save_change_to_practice_id?

    errors.add(:base, "an approved connection cannot be reassigned")
  end
end
