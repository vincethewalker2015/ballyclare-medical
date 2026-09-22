class AppointmentHold < ApplicationRecord
  belongs_to :appointment_slot
  belongs_to :patient

  validates :expires_at, presence: true

  scope :active, -> { where("expires_at > ?", Time.current) }
  scope :expired, -> { where(expires_at: ..Time.current) }

  def expired?
    expires_at <= Time.current
  end
end
