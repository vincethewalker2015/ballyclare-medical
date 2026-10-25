module Appointments
  class AvailableStaffSlots
    def initialize(practice:, clinician:, date: nil)
      @practice = practice
      @clinician = clinician
      @date = date
    end

    def call
      now = Time.current
      slots = @practice.appointment_slots
        .joins(:availability_block)
        .merge(AvailabilityBlock.active)
        .where(clinician: @clinician)
        .where("appointment_slots.starts_at >= ?", now)
        .where.not(id: Appointment.where.not(status: "cancelled").select(:appointment_slot_id))
        .where.not(id: AppointmentHold.where("expires_at > ?", now).select(:appointment_slot_id))
        .order(:starts_at)

      return slots.limit(20) if @date.blank?

      selected_date = Date.iso8601(@date.to_s)
      day_start = Time.use_zone(@practice.timezone) do
        Time.zone.local(selected_date.year, selected_date.month, selected_date.day)
      end
      slots.where(appointment_slots: { starts_at: day_start...(day_start + 1.day) })
    rescue Date::Error
      slots.none
    end
  end
end
