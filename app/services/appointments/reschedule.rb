module Appointments
  class Reschedule
    class NotAllowed < StandardError; end

    def initialize(appointment:, replacement_slot:, patient_account: nil, staff_user: nil)
      @appointment, @replacement_slot = appointment, replacement_slot
      @patient_account, @staff_user = patient_account, staff_user
    end

    def call
      raise NotAllowed, "An authenticated actor is required" unless @patient_account.present? ^ @staff_user.present?

      AppointmentSlot.transaction do
        # The clinician lock serializes reschedules with ordinary bookings.
        StaffMember.lock.find(@replacement_slot.clinician_id)
        @replacement_slot.with_lock do
          @appointment.lock!
          validate!
          original_slot = @appointment.appointment_slot
          original_clinician = @appointment.clinician

          @appointment.update!(appointment_slot: @replacement_slot, clinician: @replacement_slot.clinician)
          AuditEvent.create!(
            practice: @appointment.practice, user: @staff_user,
            action: "appointment.rescheduled", auditable: @appointment,
            metadata: {
              actor_type: @patient_account ? "patient" : "staff",
              patient_account_id: @patient_account&.id,
              old_slot_id: original_slot.id, new_slot_id: @replacement_slot.id,
              old_clinician_id: original_clinician.id,
              new_clinician_id: @replacement_slot.clinician_id,
              old_starts_at: original_slot.starts_at.iso8601,
              new_starts_at: @replacement_slot.starts_at.iso8601
            }
          )
        end
      end
      @appointment
    end

    private

    def validate!
      raise NotAllowed, "Only booked or confirmed appointments may be rescheduled" unless @appointment.status.in?(%w[booked confirmed])
      raise NotAllowed, "The original appointment has already started" if @appointment.appointment_slot.starts_at <= Time.current
      if @patient_account
        approved = @patient_account.patient_account_links.approved.exists?(
          patient_id: @appointment.patient_id, practice_id: @appointment.practice_id
        )
        raise NotAllowed, "Patient access is not approved" unless approved
        raise NotAllowed, "Rescheduling requires at least 24 hours notice" if @appointment.appointment_slot.starts_at < 24.hours.from_now
      end
      raise NotAllowed, "Replacement slot belongs to another practice" unless @replacement_slot.practice_id == @appointment.practice_id
      raise NotAllowed, "Clinician type must remain the same" unless @replacement_slot.clinician.staff_type == @appointment.clinician.staff_type
      raise NotAllowed, "Replacement clinician is inactive" unless @replacement_slot.clinician.active?
      raise NotAllowed, "Replacement availability is inactive" unless @replacement_slot.availability_block.active?
      if @patient_account && !@replacement_slot.availability_block.bookable_online?
        raise NotAllowed, "Replacement slot is not available online"
      end
      raise NotAllowed, "Replacement slot must be in the future" if @replacement_slot.starts_at <= Time.current
      raise NotAllowed, "Choose a different appointment slot" if @replacement_slot.id == @appointment.appointment_slot_id
      if Appointment.where(appointment_slot_id: @replacement_slot.id).where.not(status: "cancelled").exists? ||
          AppointmentHold.active.exists?(appointment_slot_id: @replacement_slot.id)
        raise NotAllowed, "Replacement slot is no longer available"
      end
      if @appointment.payments.where(status: %w[pending processing]).exists?
        raise NotAllowed, "Cannot reschedule while a payment is in progress"
      end
      # Fees are configured by clinician type; same-type reschedules retain existing charges.
    end
  end
end
