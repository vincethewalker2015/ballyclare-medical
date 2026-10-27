module GuestBookings
  module PracticeConsistency
    def self.valid?(guest:, slot:)
      block = slot.availability_block
      clinician = slot.clinician

      guest.practice_id == slot.practice_id &&
        guest.appointment_slot_id == slot.id &&
        block.practice_id == slot.practice_id &&
        block.clinician_id == clinician.id &&
        clinician.practice_id == slot.practice_id
    end
  end
end
