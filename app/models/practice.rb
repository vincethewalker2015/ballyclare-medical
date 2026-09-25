class Practice < ApplicationRecord
  has_many :patients, dependent: :restrict_with_error
  has_many :staff_members, dependent: :restrict_with_error
  has_many :availability_blocks, dependent: :restrict_with_error
  has_many :appointment_slots, dependent: :restrict_with_error
  has_many :appointments, dependent: :restrict_with_error
  has_many :encounters, dependent: :restrict_with_error
  has_many :audit_events, dependent: :restrict_with_error

  validates :name, :timezone, :currency, :country_code, presence: true
end
