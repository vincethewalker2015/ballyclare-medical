class ClinicalNote < ApplicationRecord
  belongs_to :patient
  belongs_to :encounter
  belongs_to :author, class_name: "StaffMember"

  validates :note_type, :body, presence: true
end
