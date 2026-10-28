module Payments
  class EmergencyUnpaidBookingPolicy
    def initialize(practice:, payment:)
      @practice = practice
      @payment = payment
    end

    def allowed?
      payment.nil? && Payments::StripeOutageDeclaration.active?(practice: practice)
    end

    private

    attr_reader :practice, :payment
  end
end
