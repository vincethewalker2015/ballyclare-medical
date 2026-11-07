module Payments
  # Only retrieves an existing PaymentIntent. Never creates a second charge.
  class ResumeOutstandingPayment
    Result = Struct.new(:status, :client_secret, keyword_init: true)

    def initialize(payment:)
      @payment = payment
    end

    def call
      unless payment.appointment_id.present? && payment.provider == "stripe" &&
          payment.status == "processing" && payment.provider_payment_id.present?
        return Result.new(status: :pending)
      end

      intent = PaymentProviders::StripeProvider::CreatePayment.new(payment: payment).call
      return Result.new(status: :pending) unless intent.id == payment.provider_payment_id

      case intent.status
      when "requires_payment_method", "requires_confirmation", "requires_action"
        Result.new(status: :checkout, client_secret: intent.client_secret)
      when "succeeded"
        Payments::HandleSucceeded.new(payment_intent: intent).call
        Result.new(status: :succeeded)
      when "canceled"
        begin
          Payments::ReconcileAppointmentPayment.new(payment: payment).call
          Result.new(status: :cancelled)
        rescue Payments::ReconcileAppointmentPayment::PaymentNotReconciliable
          Result.new(status: :pending)
        end
      else
        Result.new(status: :pending)
      end
    end

    private

    attr_reader :payment
  end
end
