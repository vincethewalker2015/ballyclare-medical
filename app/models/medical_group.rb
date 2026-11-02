class MedicalGroup < ApplicationRecord
  has_many :practices, dependent: :restrict_with_error

  validates :name, presence: true
end
