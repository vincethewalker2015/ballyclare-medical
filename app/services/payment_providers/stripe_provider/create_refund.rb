module PaymentProviders
  module StripeProvider
    class CreateRefund
      class ProviderRefundMismatch < StandardError; end

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

        refund.with_lock do
          if refund.provider_refund_id.present? &&
             refund.provider_refund_id != stripe_refund.id
            raise ProviderRefundMismatch,
                  "Stripe refund ID does not match local refund"
          end

          unless refund.status == "succeeded"
            refund.update!(
              provider_refund_id: stripe_refund.id,
              status: "processing"
            )
          end
        end

        stripe_refund
      end

      private

      attr_reader :refund
    end
  end
end
