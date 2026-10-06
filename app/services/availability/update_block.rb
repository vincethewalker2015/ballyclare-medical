module Availability
  class UpdateBlock
    class Unavailable < StandardError; end

    def initialize(
      availability_block:,
      clinician:,
      starts_at:,
      ends_at:,
      slot_duration_minutes:,
      bookable_online:
    )
      @availability_block = availability_block
      @clinician = clinician
      @starts_at = starts_at
      @ends_at = ends_at
      @slot_duration_minutes = slot_duration_minutes
      @bookable_online = bookable_online
    end

    def call
      AvailabilityBlock.transaction do
        availability_block.lock!

        slots = availability_block
          .appointment_slots
          .lock
          .to_a

        ensure_slots_can_be_rebuilt!(slots)

        slots.each(&:destroy!)

        availability_block.update!(
          clinician: clinician,
          starts_at: starts_at,
          ends_at: ends_at,
          slot_duration_minutes: slot_duration_minutes,
          bookable_online: bookable_online
        )

        Availability::GenerateSlots.new(
          availability_block
        ).call
      end

      availability_block
    end

    private

    attr_reader :availability_block,
                :clinician,
                :starts_at,
                :ends_at,
                :slot_duration_minutes,
                :bookable_online

    def ensure_slots_can_be_rebuilt!(slots)
      slot_ids = slots.map(&:id)

      return if slot_ids.empty?

      if Appointment.where(appointment_slot_id: slot_ids).exists?
        raise Unavailable,
              "Availability with booked appointments cannot be rescheduled."
      end

      if AppointmentHold.where(appointment_slot_id: slot_ids).exists?
        raise Unavailable,
              "Availability with appointment hold history cannot be rescheduled."
      end
    end
  end
end
