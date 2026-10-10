
module Payments
  class HandleSucceeded
    class PaymentNotFound < StandardError; end
    class AmountMismatch < StandardError; end
    class CurrencyMismatch < StandardError; end

    def initialize(payment_intent:)
      @payment_intent = payment_intent
    end

    def call
      payment = find_payment!

      if payment.appointment_id.present?
        appointment = Appointment.find(payment.appointment_id)

        appointment.with_lock do
          process_payment!(payment)
        end
      else
        process_payment!(payment)
      end
    end

    private

    attr_reader :payment_intent

    def find_payment!
      payment = Payment.find_by(
        provider: "stripe",
        provider_payment_id: payment_intent.id
      )

      return payment if payment

      payment_id = payment_intent.metadata&.[]("payment_id")

      if payment_id.present?
        payment = Payment.find_by(
          id: payment_id,
          provider: "stripe"
        )

        return payment if payment
      end

      raise PaymentNotFound,
            "Payment not found for Stripe PaymentIntent #{payment_intent.id}"
    end

    def process_payment!(payment)
      payment.with_lock do
        validate_amount!(payment)
        validate_currency!(payment)

        if payment.provider_payment_id.present? &&
           payment.provider_payment_id != payment_intent.id
          raise PaymentNotFound,
                "Payment is associated with a different Stripe PaymentIntent"
        end

        if payment.provider_payment_id.nil?
          payment.update!(
            provider_payment_id: payment_intent.id
          )
        end

        return payment if payment.status == "requires_refund"

        unless payment.status == "succeeded"
          payment.update!(
            status: "succeeded",
            paid_at: Time.current
          )
        end

        return payment if payment.appointment.present?

        complete_booking!(payment)

        payment
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
