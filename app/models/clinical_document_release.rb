class ClinicalDocumentRelease < ApplicationRecord
  belongs_to :practice
  belongs_to :patient
  belongs_to :encounter
  belongs_to :released_by, class_name: "StaffMember"

  after_create_commit :refresh_patient_documents

  def refresh_patient_documents
    PatientAccountLink.approved.where(practice_id: practice_id, patient_id: patient_id).find_each do |link|
      Turbo::StreamsChannel.broadcast_refresh_to(link, :clinical_documents)
    end
  end

  validates :title, :body, :released_at, presence: true
  validate :matching_practice_and_patient
  validate :immutable_after_release, on: :update

  private

  def matching_practice_and_patient
    return if practice.blank? || patient.blank? || encounter.blank? || released_by.blank?
    unless patient.practice_id == practice.id &&
        encounter.practice_id == practice.id &&
        encounter.patient_id == patient.id &&
        released_by.practice_id == practice.id &&
        released_by.id == encounter.clinician_id
      errors.add(:base, "Clinical document must belong to the encounter practice and clinician")
    end
  end

  def immutable_after_release
    errors.add(:base, "Released documents cannot be edited")
  end
end
