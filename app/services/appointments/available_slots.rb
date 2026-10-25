module Appointments
  class AvailableSlots
    def initialize(practice:, clinician:, date: nil, online_only: false, limit: 20)
      @practice, @clinician, @date = practice, clinician, date
      @online_only, @limit = online_only, limit
    end

    def call
      now = Time.current
      scope = @practice.appointment_slots
        .joins(:availability_block)
        .merge(AvailabilityBlock.active)
        .where(clinician: @clinician)
        .where("appointment_slots.starts_at >= ?", now)
        .where.not(id: Appointment.where.not(status: "cancelled").select(:appointment_slot_id))
        .where.not(id: AppointmentHold.active.select(:appointment_slot_id))
        .order(:starts_at)
      scope = scope.where(availability_blocks: { bookable_online: true }) if @online_only
      return scope.limit(@limit) if @date.blank?

      date = Date.iso8601(@date.to_s)
      start_at = Time.use_zone(@practice.timezone) { Time.zone.local(date.year, date.month, date.day) }
      scope.where(appointment_slots: { starts_at: start_at...(start_at + 1.day) })
    rescue Date::Error
      scope.none
    end
  end
end
