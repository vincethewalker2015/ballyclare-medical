module Payments
  class ReconcileProcessingRefunds
    def initialize(refunds:)
      @refunds = refunds
    end

    def call
      @refunds.each do |refund|
        next unless refund.status == "processing"
        next if refund.updated_at > 5.seconds.ago

        begin
          Payments::ReconcileRefund.new(refund: refund).call
        rescue Stripe::StripeError => error
          Rails.logger.warn("Stripe refund reconciliation unavailable for refund #{refund.id}: #{error.class}")
        rescue Payments::ReconcileRefund::MissingProviderRefundId,
               Payments::ReconcileRefund::ProviderRefundMismatch,
               Payments::ReconcileRefund::PaymentMismatch,
               Payments::ReconcileRefund::AmountMismatch,
               Payments::ReconcileRefund::CurrencyMismatch,
               Payments::HandleRefundSucceeded::RefundNotFound,
               Payments::HandleRefundSucceeded::ProviderRefundMismatch,
               Payments::HandleRefundSucceeded::PaymentMismatch,
               Payments::HandleRefundSucceeded::AmountMismatch,
               Payments::HandleRefundSucceeded::CurrencyMismatch => error
          Rails.logger.error("Stripe refund reconciliation requires investigation for refund #{refund.id}: #{error.class}")
        end
      end
    end
  end
end
