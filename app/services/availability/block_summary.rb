module Availability
  class BlockSummary
    def initialize(availability_block:, now: Time.current)
      @availability_block = availability_block
      @now = now
    end

    def total_slots
      slots.size
    end

    def booked_slots
      slots.count { |slot| slot.appointment.present? }
    end

    def held_slots
      slots.count do |slot|
        slot.appointment.nil? &&
          slot.appointment_holds.any? { |hold| hold.expires_at > now }
      end
    end

    def available_slots
      total_slots - booked_slots - held_slots
    end

    private

    attr_reader :availability_block, :now

    def slots
      availability_block.appointment_slots
    end
  end
end
