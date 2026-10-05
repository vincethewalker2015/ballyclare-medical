require "rails_helper"

RSpec.describe Payments::TakeAppointmentPayment do
  describe "#call" do
    let(:appointment) { create(:appointment) }

    let(:payment_intent) do
      instance_double(
        Stripe::PaymentIntent,
        id: "pi_test_123",
        client_secret: "pi_test_secret"
      )
    end

    let(:stripe_provider) do
      instance_double(
        PaymentProviders::StripeProvider::CreatePayment,
        call: payment_intent
      )
    end

    before do
      create(
        :appointment_charge,
        appointment: appointment,
        patient: appointment.patient,
        practice: appointment.practice,
        amount_cents: 5000,
        status: "active"
      )

      allow(
        PaymentProviders::StripeProvider::CreatePayment
      ).to receive(:new)
        .and_return(stripe_provider)
    end

    subject(:call_service) do
      described_class.new(
        appointment: appointment,
        amount_cents: 5000
      ).call
    end

    it "creates a payment for the appointment" do
      expect { call_service }
        .to change(Payment, :count)
        .by(1)

      payment = Payment.last

      expect(payment).to have_attributes(
        appointment: appointment,
        patient: appointment.patient,
        amount_cents: 5000,
        currency: appointment.practice.currency
      )
    end

    it "sends the created payment to the Stripe provider" do
      result = call_service

      expect(
        PaymentProviders::StripeProvider::CreatePayment
      ).to have_received(:new)
        .with(payment: result.payment)

      expect(stripe_provider)
        .to have_received(:call)
    end

    it "returns the payment and Stripe payment intent" do
      result = call_service

      expect(result).to be_a(
        Payments::TakeAppointmentPayment::Result
      )

      expect(result.payment).to be_a(Payment)
      expect(result.payment_intent).to eq(payment_intent)
    end

    it "marks the payment as failed when Stripe cannot create the payment intent" do
      allow(stripe_provider)
        .to receive(:call)
        .and_raise(
          Stripe::APIConnectionError.new("Stripe is unavailable")
        )

      expect {
        call_service
      }.to raise_error(Stripe::APIConnectionError)

      expect(Payment.last.status).to eq("failed")
    end
  end
end
