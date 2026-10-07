module Availability
  class CancelBlock
    class Unavailable < StandardError; end

    def initialize(availability_block:)
      @availability_block = availability_block
    end

    def call
      AvailabilityBlock.transaction do
        availability_block.lock!

        return availability_block if availability_block.cancelled?

        ensure_no_booked_appointments!

        availability_block.update!(
          cancelled_at: Time.current
        )
      end

      availability_block
    end

    private

    attr_reader :availability_block

    def ensure_no_booked_appointments!
      if Appointment
           .joins(:appointment_slot)
           .where(
             appointment_slots: {
               availability_block_id: availability_block.id
             }
           )
           .exists?
        raise Unavailable,
              "Availability with booked appointments cannot be cancelled."
      end
    end
  end
end
