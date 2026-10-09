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
      slots.count { |slot| booked?(slot) }
    end

    def held_slots
      slots.count do |slot|
        !booked?(slot) &&
          slot.appointment_holds.any? { |hold| hold.expires_at > now }
      end
    end

    def available_slots
      return 0 unless availability_block.active?

      slots.count do |slot|
        slot.starts_at > now &&
          !booked?(slot) &&
          slot.appointment_holds.none? { |hold| hold.expires_at > now }
      end
    end

    private

    attr_reader :availability_block, :now

    def slots
      @slots ||= availability_block.appointment_slots.includes(
        :appointments,
        :appointment_holds
      ).to_a
    end

    def booked?(slot)
      slot.appointments.any? { |appointment| appointment.status != "cancelled" }
    end
  end
end
