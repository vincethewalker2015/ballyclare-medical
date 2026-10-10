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

        if payment.appointment_id.present?
          appointment = Appointment.find(payment.appointment_id)

          appointment.with_lock do
            payment.with_lock do
              if payment.provider_payment_id.present? &&
                payment.provider_payment_id != payment_intent.id
                raise "Payment is associated with a different Stripe PaymentIntent"
              end

              payment.update!(
                provider_payment_id: payment_intent.id,
                status: payment.status == "pending" ? "processing" : payment.status
              )
            end
          end
        else
          payment.with_lock do
            if payment.provider_payment_id.present? &&
              payment.provider_payment_id != payment_intent.id
              raise "Payment is associated with a different Stripe PaymentIntent"
            end

            payment.update!(
              provider_payment_id: payment_intent.id,
              status: payment.status == "pending" ? "processing" : payment.status
            )
          end
        end

        payment_intent
      end

      private

      attr_reader :payment
    end
  end
end
