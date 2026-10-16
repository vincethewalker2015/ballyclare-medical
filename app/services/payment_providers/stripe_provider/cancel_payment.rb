module PaymentProviders
  module StripeProvider
    class CancelPayment
      class CancellationNotConfirmed < StandardError; end

      def initialize(payment:, payment_intent_id: nil)
        @payment = payment
        @payment_intent_id = payment_intent_id || payment.provider_payment_id
      end

      def call
        if payment_intent_id.blank?
          raise ArgumentError, "Stripe PaymentIntent ID is missing"
        end

        payment_intent = Stripe::PaymentIntent.cancel(
          payment_intent_id
        )

        unless payment_intent.id == payment_intent_id &&
               payment_intent.status == "canceled"
          raise CancellationNotConfirmed,
                "Stripe did not confirm PaymentIntent cancellation"
        end

        payment_intent
      end

      private

      attr_reader :payment, :payment_intent_id
    end
  end
end
