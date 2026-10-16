class AppointmentSlot < ApplicationRecord
  HOLD_DURATION = 10.minutes

  class Unavailable < StandardError; end
  class PracticeMismatch < StandardError; end

  belongs_to :practice
  belongs_to :clinician, class_name: "StaffMember"
  belongs_to :availability_block

  has_many :appointments, dependent: :restrict_with_error
  has_many :appointment_holds, dependent: :restrict_with_error

  validates :starts_at, :ends_at, presence: true

  validate :ends_after_it_starts

  scope :upcoming, -> { where(starts_at: Time.current..) }

  def hold_for!(patient:)
    raise ArgumentError, "patient is required" unless patient

    self.class.transaction do
      StaffMember.lock.find(clinician_id)

      with_lock do
        ensure_patient_belongs_to_practice!(patient)
        ensure_available_for_hold!

        appointment_holds.create!(
          patient: patient,
          expires_at: HOLD_DURATION.from_now
        )
      end
    end
  end

  private

  def ends_after_it_starts
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, "must be after starts_at") if ends_at <= starts_at
  end

  def ensure_patient_belongs_to_practice!(patient)
    return if patient.practice_id == practice_id

    raise PracticeMismatch,
          "Patient and appointment slot must belong to the same practice"
  end

  def ensure_available_for_hold!
    unless availability_block.active?
      raise Unavailable,
            "Appointment slot is no longer available"
    end

    if starts_at <= Time.current
      raise Unavailable,
            "Appointment slot is no longer in the future"
    end

    if Appointment.where(appointment_slot_id: id)
                  .where.not(status: "cancelled")
                  .exists?
      raise Unavailable,
            "Appointment slot has already been booked"
    end

    if AppointmentHold.active.exists?(appointment_slot_id: id)
      raise Unavailable,
            "Appointment slot is currently being held"
    end
  end
end
