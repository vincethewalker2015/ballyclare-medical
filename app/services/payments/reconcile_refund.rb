module Payments
  class ReconcileRefund
    class MissingProviderRefundId < StandardError; end
    class ProviderRefundMismatch < StandardError; end
    class PaymentMismatch < StandardError; end
    class AmountMismatch < StandardError; end
    class CurrencyMismatch < StandardError; end

    def initialize(refund:)
      @refund = refund
    end

    def call
      return refund unless refund.status == "processing"

      if refund.provider_refund_id.blank?
        raise MissingProviderRefundId,
              "Cannot reconcile refund #{refund.id} without a Stripe refund ID"
      end

      stripe_refund = Stripe::Refund.retrieve(refund.provider_refund_id)

      case stripe_refund.status
      when "succeeded"
        Payments::HandleRefundSucceeded.new(
          stripe_refund: stripe_refund
        ).call
      when "failed"
        record_failure(stripe_refund)
      else
        refund
      end
    end

    private

    attr_reader :refund

    def record_failure(stripe_refund)
      refund.with_lock do
        validate_stripe_refund!(stripe_refund)

        return refund unless refund.status == "processing"

        refund.update!(status: "failed")
      end

      refund
    end

    def validate_stripe_refund!(stripe_refund)
      unless stripe_refund.id == refund.provider_refund_id
        raise ProviderRefundMismatch,
              "Stripe refund ID does not match local refund"
      end

      unless stripe_refund.payment_intent ==
             refund.payment.provider_payment_id
        raise PaymentMismatch,
              "Stripe refund payment does not match local payment"
      end

      unless stripe_refund.amount == refund.amount_cents
        raise AmountMismatch,
              "Stripe refund amount does not match local refund"
      end

      unless stripe_refund.currency.to_s.casecmp?(refund.currency)
        raise CurrencyMismatch,
              "Stripe refund currency does not match local refund"
      end
    end
  end
end
