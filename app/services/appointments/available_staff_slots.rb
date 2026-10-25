module Appointments
  class AvailableStaffSlots
    def initialize(practice:, clinician:, date: nil)
      @practice, @clinician, @date = practice, clinician, date
    end

    def call
      AvailableSlots.new(practice: @practice, clinician: @clinician, date: @date).call
    end
  end
end
