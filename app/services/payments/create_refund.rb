module Payments
  class CreateRefund
    class PaymentNotRefundable < StandardError; end
    class AmountExceedsRefundable < StandardError; end
    class CurrencyMismatch < StandardError; end

    COUNTED_STATUSES = %w[pending processing succeeded].freeze

    def initialize(payment:, amount_cents:, requested_by: nil, reason: nil)
      @payment = payment
      @amount_cents = amount_cents
      @requested_by = requested_by
      @reason = reason
    end

    def call
      Payment.transaction do
        payment.lock!

        validate_payment!
        validate_currency!

        refundable_cents = payment.amount_cents - already_refunded_cents

        if amount_cents > refundable_cents
          raise AmountExceedsRefundable,
                "Refund amount exceeds remaining refundable amount"
        end

        payment.refunds.create!(
          amount_cents: amount_cents,
          currency: payment.currency,
          status: "pending",
          requested_at: Time.current,
          requested_by: requested_by,
          reason: reason,
          idempotency_key: SecureRandom.uuid
        )
      end
    end

    private

      attr_reader :payment, :amount_cents, :requested_by, :reason

    def validate_payment!
      return if %w[succeeded requires_refund].include?(payment.status)

      raise PaymentNotRefundable,
            "Payment must have succeeded before it can be refunded"
    end

    def validate_currency!
      return if payment.currency.present?

      raise CurrencyMismatch,
            "Payment currency is required"
    end

    def already_refunded_cents
      payment.refunds
             .where(status: COUNTED_STATUSES)
             .sum(:amount_cents)
    end
  end
end
