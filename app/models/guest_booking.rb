class GuestBooking < ApplicationRecord
  belongs_to :practice
  belongs_to :appointment_slot
  belongs_to :patient, optional: true

  validates :first_name, :last_name, :date_of_birth, :email, :phone, :consultation_reason, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :status, inclusion: { in: %w[ draft payment_pending completed expired ] }
  validate :slot_belongs_to_practice
  validate :date_of_birth_not_in_future

  private

  def slot_belongs_to_practice
    return unless practice && appointment_slot

    errors.add(:appointment_slot, "must belong to the selected practice") if appointment_slot.practice_id != practice.id
  end

  def date_of_birth_not_in_future
    errors.add(:date_of_birth, "cannot be in the future") if date_of_birth && date_of_birth > Date.current
  end
end
