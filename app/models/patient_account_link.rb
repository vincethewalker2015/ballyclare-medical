class PatientAccountLink < ApplicationRecord
  STATUSES = %w[pending approved revoked].freeze

  belongs_to :practice
  belongs_to :patient
  belongs_to :patient_account
  belongs_to :verified_by, class_name: "StaffMember", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :patient_id, uniqueness: true
  validates :patient_account_id, uniqueness: { scope: :practice_id }
  validates :verification_method, :verified_at, :verified_by, :approved_at,
    presence: true, if: :approved?
  validate :patient_belongs_to_practice
  validate :verifier_belongs_to_practice
  validate :account_is_confirmed_before_approval
  validate :approved_link_cannot_be_reassigned, on: :update

  scope :approved, -> { where(status: "approved") }

  def approved?
    status == "approved"
  end

  private

  def patient_belongs_to_practice
    return if patient.nil? || practice.nil? || patient.practice_id == practice.id

    errors.add(:patient, "must belong to the same practice")
  end

  def verifier_belongs_to_practice
    return if verified_by.nil? || practice.nil?
    return if verified_by.practice_id == practice.id && verified_by.active? &&
      verified_by.staff_administration_access?

    errors.add(:verified_by, "must be an active practice administrator")
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
