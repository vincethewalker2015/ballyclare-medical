module Payments
  class EmergencyUnpaidBookingPolicy
    def initialize(outage_confirmed:, payment:)
      @outage_confirmed = outage_confirmed
      @payment = payment
    end

    def allowed?
      outage_confirmed == true && payment.nil?
    end

    private

    attr_reader :outage_confirmed, :payment
  end
end
