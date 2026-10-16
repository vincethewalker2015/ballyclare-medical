module Payments
  class HandleRefundSucceeded
    class RefundNotFound < StandardError; end
    class AmountMismatch < StandardError; end
    class CurrencyMismatch < StandardError; end
    class PaymentMismatch < StandardError; end
    class ProviderRefundMismatch < StandardError; end

    def initialize(stripe_refund:)
      @stripe_refund = stripe_refund
    end

    def call
      refund = find_refund

      refund.with_lock do
        validate_provider_refund_id!(refund)
        validate_payment!(refund)
        validate_amount!(refund)
        validate_currency!(refund)

        return refund if refund.status == "succeeded"

        refund.update!(
          provider_refund_id: stripe_refund.id,
          status: "succeeded",
          refunded_at: Time.current
        )
      end

      refund
    end

    private

    attr_reader :stripe_refund

    def find_refund
      existing = Refund.find_by(
        provider_refund_id: stripe_refund.id
      )

      return existing if existing

      refund_id = stripe_refund.metadata&.refund_id

      refund = Refund.find_by(id: refund_id) if refund_id.present?

      return refund if refund

      raise RefundNotFound,
            "Refund not found for Stripe refund #{stripe_refund.id}"
    end

    def validate_provider_refund_id!(refund)
      return if refund.provider_refund_id.blank?
      return if refund.provider_refund_id == stripe_refund.id

      raise ProviderRefundMismatch,
            "Stripe refund ID does not match local refund"
    end

    def validate_payment!(refund)
      metadata_payment_id = stripe_refund.metadata&.payment_id

      if metadata_payment_id.present? &&
         metadata_payment_id != refund.payment_id
        raise PaymentMismatch,
              "Stripe refund payment does not match local payment"
      end

      stripe_payment_intent = stripe_refund.payment_intent

      return if stripe_payment_intent.blank?
      return if stripe_payment_intent == refund.payment.provider_payment_id

      raise PaymentMismatch,
            "Stripe refund PaymentIntent does not match local payment"
    end

    def validate_amount!(refund)
      return if refund.amount_cents == stripe_refund.amount

      raise AmountMismatch,
            "Stripe refund amount does not match local refund"
    end

    def validate_currency!(refund)
      return if refund.currency.casecmp?(stripe_refund.currency)

      raise CurrencyMismatch,
            "Stripe refund currency does not match local refund"
    end
  end
end
