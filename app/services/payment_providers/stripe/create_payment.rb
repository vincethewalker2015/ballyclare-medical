module PaymentProviders
  module Stripe
    class CreatePayment
      def initialize(payment:)
        @payment = payment
      end

      def call
        raise NotImplementedError, "Stripe payment creation is not implemented yet"
      end

      private

      attr_reader :payment
    end
  end
end
