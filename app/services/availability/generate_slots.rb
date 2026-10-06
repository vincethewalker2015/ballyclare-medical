module Availability
  class GenerateSlots
    def initialize(availability_block)
      @availability_block = availability_block
    end

    def call
      generate_slots
    end

    private

    attr_reader :availability_block

    def generate_slots
      current_start = availability_block.starts_at
      duration = availability_block.slot_duration_minutes.minutes

      while current_start + duration <= availability_block.ends_at
        AppointmentSlot.find_or_create_by!(
          availability_block: availability_block,
          clinician: availability_block.clinician,
          starts_at: current_start
        ) do |slot|
          slot.practice = availability_block.practice
          slot.ends_at = current_start + duration
        end

        current_start += duration
      end
    end
  end
end
