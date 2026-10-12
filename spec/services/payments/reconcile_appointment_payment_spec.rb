
require "rails_helper"

RSpec.describe Payments::ReconcileAppointmentPayment do
  describe "#call" do
    it "marks a processing payment as cancelled when Stripe confirms cancellation" do
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

      payment_intent = double(
        id: "pi_123",
        status: "canceled"
      )

      expect(Stripe::PaymentIntent)
        .to receive(:retrieve)
        .with("pi_123")
        .and_return(payment_intent)

      result = described_class.new(payment: payment).call

      expect(result).to eq(payment)
      expect(payment.reload.status).to eq("cancelled")
    end

    it "rejects a Stripe response with a different PaymentIntent ID" do
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

      payment_intent = double(
        id: "pi_different",
        status: "canceled"
      )

      expect(Stripe::PaymentIntent)
        .to receive(:retrieve)
        .with("pi_original")
        .and_return(payment_intent)

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        Payments::ReconcileAppointmentPayment::PaymentNotReconciliable
      )

      expect(payment.reload.status).to eq("processing")
    end

    it "rejects reconciliation if the payment's PaymentIntent ID changes during retrieval" do
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

      allow(Stripe::PaymentIntent)
        .to receive(:retrieve)
        .with("pi_original") do
          payment.update!(provider_payment_id: "pi_replacement")

          double(
            id: "pi_original",
            status: "canceled"
          )
        end

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        Payments::ReconcileAppointmentPayment::PaymentNotReconciliable
      )

      expect(payment.reload.status).to eq("processing")
      expect(payment.provider_payment_id).to eq("pi_replacement")
    end

    it "does not overwrite a payment that succeeds during Stripe retrieval" do
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

      allow(Stripe::PaymentIntent)
        .to receive(:retrieve)
        .with("pi_123") do
          # Simulate a successful-payment webhook arriving
          # while reconciliation is waiting for Stripe.
          payment.update!(status: "succeeded")

          double(
            id: "pi_123",
            status: "canceled"
          )
        end

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        Payments::ReconcileAppointmentPayment::PaymentNotReconciliable
      )

      expect(payment.reload.status).to eq("succeeded")
    end

    it "does not cancel a payment when Stripe reports processing" do
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

      payment_intent = double(
        id: "pi_123",
        status: "processing"
      )

      expect(Stripe::PaymentIntent)
        .to receive(:retrieve)
        .with("pi_123")
        .and_return(payment_intent)

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        Payments::ReconcileAppointmentPayment::PaymentNotReconciliable
      )

      expect(payment.reload.status).to eq("processing")
    end

    it "leaves the payment unchanged when Stripe retrieval fails" do
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

      allow(Stripe::PaymentIntent)
        .to receive(:retrieve)
        .with("pi_123")
        .and_raise(
          Stripe::APIConnectionError.new("Stripe connection failed")
        )

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(Stripe::APIConnectionError)

      expect(payment.reload.status).to eq("processing")
    end

    it "rejects a payment without a Stripe PaymentIntent ID" do
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

      expect(Stripe::PaymentIntent)
        .not_to receive(:retrieve)

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        Payments::ReconcileAppointmentPayment::PaymentNotReconciliable
      )

      expect(payment.reload.status).to eq("pending")
      expect(payment.provider_payment_id).to be_nil
    end

    it "rejects a non-Stripe payment without contacting Stripe" do
      appointment = create(:appointment)

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "other",
        provider_payment_id: "external_123",
        status: "processing"
      )

      expect(Stripe::PaymentIntent)
        .not_to receive(:retrieve)

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        Payments::ReconcileAppointmentPayment::PaymentNotReconciliable
      )

      expect(payment.reload.status).to eq("processing")
    end
  end
end
