module Payments
  class HandleRefundSucceeded
    class RefundNotFound < StandardError; end
    class AmountMismatch < StandardError; end
    class CurrencyMismatch < StandardError; end

    def initialize(stripe_refund:)
      @stripe_refund = stripe_refund
    end

    def call
      refund = find_refund

      refund.with_lock do
        validate_amount!(refund)
        validate_currency!(refund)

        return refund if refund.status == "succeeded"

        refund.update!(
          status: "succeeded",
          refunded_at: Time.current
        )
      end

      refund
    end

    private

      attr_reader :stripe_refund

    def find_refund
      Refund.find_by(
        provider_refund_id: stripe_refund.id
      ) || raise(
        RefundNotFound,
        "Refund not found for Stripe refund #{stripe_refund.id}"
      )
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
