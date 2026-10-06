module PaymentProviders
  module StripeProvider
    class CreateRefund
      def initialize(refund:)
        @refund = refund
      end

      def call
        stripe_refund = Stripe::Refund.create(
          {
            payment_intent: refund.payment.provider_payment_id,
            amount: refund.amount_cents,
            metadata: {
              refund_id: refund.id,
              payment_id: refund.payment_id
            }
          },
          {
            idempotency_key: refund.idempotency_key
          }
        )

        refund.update!(
          provider_refund_id: stripe_refund.id,
          status: "processing"
        )

        stripe_refund
      end

      private

      attr_reader :refund
    end
  end
end
