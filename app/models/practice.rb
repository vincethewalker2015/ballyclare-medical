class Practice < ApplicationRecord
  belongs_to :medical_group

  before_validation :assign_medical_group, on: :create
  has_many :consultation_fees, dependent: :restrict_with_error
  has_many :patients, dependent: :restrict_with_error
  has_many :patient_account_links, dependent: :restrict_with_error
  has_many :patient_registration_requests, dependent: :restrict_with_error
  has_many :staff_members, dependent: :restrict_with_error
  has_many :availability_blocks, dependent: :restrict_with_error
  has_many :appointment_slots, dependent: :restrict_with_error
  has_many :appointment_charges, dependent: :restrict_with_error
  has_many :appointments, dependent: :restrict_with_error
  has_many :encounters, dependent: :restrict_with_error
  has_many :audit_events, dependent: :restrict_with_error

  validates :name, :timezone, :currency, :country_code, presence: true

  private

  def assign_medical_group
    return if medical_group || medical_group_id.present? || name.blank?

    build_medical_group(name: name)
  end
end
