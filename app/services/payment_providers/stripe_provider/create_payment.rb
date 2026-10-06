module PaymentProviders
  module StripeProvider
    class CreatePayment
      def initialize(payment:)
        @payment = payment
      end

      def call
        payment_intent = Stripe::PaymentIntent.create(
          {
            amount: payment.amount_cents,
            currency: payment.currency.downcase,
            metadata: {
              payment_id: payment.id,
              appointment_hold_id: payment.appointment_hold_id,
              appointment_id: payment.appointment_id
            }
          },
          {
            idempotency_key: payment.idempotency_key
          }
        )

        payment.update!(
          provider_payment_id: payment_intent.id,
          status: "processing"
        )

        payment_intent
      end

      private

      attr_reader :payment
    end
  end
end
