class Encounter < ApplicationRecord
  belongs_to :practice
  belongs_to :patient
  belongs_to :appointment, optional: true
  belongs_to :clinician, class_name: "StaffMember"

  has_many :clinical_notes, dependent: :restrict_with_error

  validates :encounter_type, :started_at, presence: true

  validate :ends_after_start

  private

  def ends_after_start
    return if started_at.blank? || ended_at.blank?

    errors.add(:ended_at, "must not be before started_at") if ended_at < started_at
  end
end
