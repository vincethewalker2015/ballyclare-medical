class MedicalGroup < ApplicationRecord
  belongs_to :chief_of_group, class_name: "User", optional: true
  has_many :practices, dependent: :restrict_with_error

  validates :name, presence: true
end
