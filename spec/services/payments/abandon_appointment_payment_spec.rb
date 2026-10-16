
require "rails_helper"

RSpec.describe Payments::AbandonAppointmentPayment do
  describe "#call" do
    it "marks an appointment payment cancelled after Stripe confirms cancellation" do
      appointment = create(:appointment)

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: "pi_123",
        status: "processing"
      )

      stripe_intent = double(
        "Stripe::PaymentIntent",
        id: "pi_123",
        status: "canceled"
      )

      allow(PaymentProviders::StripeProvider::CancelPayment)
        .to receive(:new)
        .with(
          payment: payment,
          payment_intent_id: "pi_123"
        )
        .and_return(double(call: stripe_intent))

      result = described_class.new(payment: payment).call

      expect(result.reload.status).to eq("cancelled")
    end

    it "does not contact Stripe for an already successful payment" do
      appointment = create(:appointment)

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: "pi_succeeded_123",
        status: "succeeded"
      )

      expect(PaymentProviders::StripeProvider::CancelPayment)
        .not_to receive(:new)

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        Payments::AbandonAppointmentPayment::PaymentNotAbandonable
      )

      expect(payment.reload.status).to eq("succeeded")
    end

    it "does not overwrite a successful payment updated during Stripe cancellation" do
      appointment = create(:appointment)

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: "pi_123",
        status: "processing"
      )

      allow(PaymentProviders::StripeProvider::CancelPayment)
        .to receive(:new)
        .with(
          payment: payment,
          payment_intent_id: "pi_123"
        ) do
          # Simulate a webhook updating the payment
          # while the Stripe cancellation is in progress.
          payment.update!(status: "succeeded")

          double(
            call: double(
              id: "pi_123",
              status: "canceled"
            )
          )
        end

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        Payments::AbandonAppointmentPayment::PaymentNotAbandonable
      )

      expect(payment.reload.status).to eq("succeeded")
    end

    it "rejects a payment without a known Stripe PaymentIntent ID" do
      appointment = create(:appointment)

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: nil,
        status: "pending"
      )

      expect(PaymentProviders::StripeProvider::CancelPayment)
        .not_to receive(:new)

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        Payments::AbandonAppointmentPayment::PaymentNotAbandonable
      )

      expect(payment.reload.status).to eq("pending")
    end

    it "rejects payments belonging to another provider" do
      appointment = create(:appointment)

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "other_provider",
        provider_payment_id: "external_123",
        status: "processing"
      )

      expect(PaymentProviders::StripeProvider::CancelPayment)
        .not_to receive(:new)

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        Payments::AbandonAppointmentPayment::PaymentNotAbandonable
      )

      expect(payment.reload.status).to eq("processing")
    end

    it "does not cancel a different PaymentIntent if the payment ID changes" do
      appointment = create(:appointment)

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: "pi_original",
        status: "processing"
      )

      allow(PaymentProviders::StripeProvider::CancelPayment)
        .to receive(:new)
        .with(
          payment: payment,
          payment_intent_id: "pi_original"
        ) do
          # Simulate another process changing the Stripe ID
          # after the initial eligibility check.
          payment.update!(
            provider_payment_id: "pi_replacement"
          )

          double(
            call: double(
              id: "pi_replacement",
              status: "canceled"
            )
          )
        end

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        Payments::AbandonAppointmentPayment::PaymentNotAbandonable
      )

      expect(payment.reload.status).to eq("processing")
    end

    it "preserves the payment when Stripe rejects cancellation" do
      appointment = create(:appointment)

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: "pi_123",
        status: "processing"
      )

      allow(PaymentProviders::StripeProvider::CancelPayment)
        .to receive(:new)
        .with(
          payment: payment,
          payment_intent_id: "pi_123"
        )
        .and_raise(
          Stripe::InvalidRequestError.new(
            "PaymentIntent cannot be canceled",
            "payment_intent"
          )
        )

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(Stripe::InvalidRequestError)

      expect(payment.reload.status).to eq("processing")
    end

    it "does not abandon a payment for an already cancelled appointment" do
      appointment = create(:appointment, status: "cancelled")

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: "pi_123",
        status: "processing"
      )

      expect(PaymentProviders::StripeProvider::CancelPayment)
        .not_to receive(:new)

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        Payments::AbandonAppointmentPayment::PaymentNotAbandonable
      )

      expect(payment.reload.status).to eq("processing")
    end

    it "rejects an appointment cancelled while Stripe cancellation is in progress" do
      appointment = create(:appointment)

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: "pi_123",
        status: "processing"
      )

      allow(PaymentProviders::StripeProvider::CancelPayment)
        .to receive(:new)
        .with(
          payment: payment,
          payment_intent_id: "pi_123"
        ) do
          # Simulate another process cancelling the appointment
          # while our Stripe request is in progress.
          appointment.update!(status: "cancelled")

          double(
            call: double(
              id: "pi_123",
              status: "canceled"
            )
          )
        end

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        Payments::AbandonAppointmentPayment::PaymentNotAbandonable
      )

      expect(payment.reload.status).to eq("processing")
    end
  end
end
