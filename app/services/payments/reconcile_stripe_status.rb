module Payments
  class ReconcileStripeStatus
    def initialize(payment:)
      @payment = payment
    end

    def call
      return payment unless payment.provider == "stripe" &&
        payment.provider_payment_id.present? &&
        payment.updated_at <= 5.seconds.ago &&
        (payment.status == "processing" ||
          (payment.status == "succeeded" &&
            payment.appointment_id.nil? &&
            payment.appointment_hold_id.present?))

      intent = Stripe::PaymentIntent.retrieve(payment.provider_payment_id)
      case intent.status
      when "succeeded"
        Payments::HandleSucceeded.new(payment_intent: intent).call
      when "canceled"
        if payment.appointment_id.present?
          Payments::ReconcileAppointmentPayment.new(payment: payment).call
        else
          Payments::HandleFailed.new(payment_intent: intent).call
        end
      when "requires_payment_method"
        Payments::HandleFailed.new(payment_intent: intent).call unless payment.appointment_id.present?
      end
      payment.reload
    end

    private

    attr_reader :payment
  end
end
