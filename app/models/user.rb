class User < ApplicationRecord
  devise :database_authenticatable,
         :registerable,
         :recoverable,
         :rememberable,
         :validatable

  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles

  has_many :staff_members, dependent: :restrict_with_error

  has_one :patient, dependent: :nullify

  has_many :appointment_status_changes,
    foreign_key: :changed_by_id,
    dependent: :restrict_with_error

  has_many :audit_events, dependent: :nullify

  has_many :requested_refunds,
    class_name: "Refund",
    foreign_key: :requested_by_id,
    dependent: :nullify
end
