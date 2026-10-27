module GuestBookings
  class ClearCompletedDetails
    SENSITIVE_ATTRIBUTES = %i[
      first_name last_name date_of_birth email phone consultation_reason
    ].freeze

    def initialize(guest_booking:)
      @guest_booking = guest_booking
    end

    def call
      return unless @guest_booking.status == "completed"
      return unless @guest_booking.patient_id.present?
      return unless @guest_booking.payment&.appointment_id.present?

      @guest_booking.update!(SENSITIVE_ATTRIBUTES.index_with { nil })
    end
  end
end
