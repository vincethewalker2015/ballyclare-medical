module Payments
  class HandleSucceeded
    class PaymentNotFound < StandardError; end
    class AmountMismatch < StandardError; end
    class CurrencyMismatch < StandardError; end

    def initialize(payment_intent:)
      @payment_intent = payment_intent
    end

    def call
      payment = find_payment

      record_success!(payment)

      return payment.reload if payment.reload.status == "requires_refund"

      complete_booking!(payment)

      payment.reload
    end

    private

    attr_reader :payment_intent

    def find_payment
      Payment.find_by(
        provider: "stripe",
        provider_payment_id: payment_intent.id
      ) || raise(
        PaymentNotFound,
        "Payment not found for Stripe PaymentIntent #{payment_intent.id}"
      )
    end

    def record_success!(payment)
      payment.with_lock do
        validate_amount!(payment)
        validate_currency!(payment)

        return if %w[succeeded requires_refund].include?(payment.status)

        payment.update!(
          status: "succeeded",
          paid_at: Time.current
        )
      end
    end

    def complete_booking!(payment)
      Payments::CompleteBooking.new(
        payment: payment
      ).call
    rescue Payments::CompleteBooking::HoldExpired,
           Payments::CompleteBooking::SlotUnavailable,
           Payments::CompleteBooking::MissingHold => e
      payment.update!(
        status: "requires_refund"
      )

      Rails.logger.error(
        "Paid Stripe payment requires refund: " \
        "payment=#{payment.id} reason=#{e.class}: #{e.message}"
      )
    end

    def validate_amount!(payment)
      return if payment.amount_cents == payment_intent.amount_received

      raise AmountMismatch,
            "Stripe payment amount does not match local payment"
    end

    def validate_currency!(payment)
      return if payment.currency.casecmp?(payment_intent.currency)

      raise CurrencyMismatch,
            "Stripe payment currency does not match local payment"
    end
  end
end
