class ClinicalNoteAmendment < ApplicationRecord
  belongs_to :clinical_note
  belongs_to :author, class_name: "StaffMember"

  validates :reason, :body, presence: true
  validates :reason, length: { maximum: 500 }
  validate :signed_consultation_and_matching_author
  validate :immutable_after_creation, on: :update
  before_destroy :prevent_destruction

  private

  def signed_consultation_and_matching_author
    return if clinical_note.blank? || author.blank?

    unless clinical_note.status == "signed" && clinical_note.note_type == "consultation" &&
        author.practice_id == clinical_note.encounter.practice_id &&
        author.active? && author.clinical_access?
      errors.add(:base, "Amendments require an authorised signed consultation note")
    end
  end

  def prevent_destruction
    errors.add(:base, "Clinical note amendments cannot be deleted")
    throw :abort
  end

  def immutable_after_creation
    errors.add(:base, "Clinical note amendments cannot be edited")
  end
end
