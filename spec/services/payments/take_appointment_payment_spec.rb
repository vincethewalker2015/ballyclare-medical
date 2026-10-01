require "rails_helper"

RSpec.describe Payments::TakeAppointmentPayment do
  describe "#call" do
    let(:appointment) { create(:appointment) }

    before do
      create(
        :appointment_charge,
        appointment: appointment,
        patient: appointment.patient,
        practice: appointment.practice,
        amount_cents: 5000,
        status: "active"
      )
    end

    let(:stripe_provider) do
      instance_double(
        PaymentProviders::StripeProvider::CreatePayment,
        call: nil
      )
    end

    before do
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
      payment = call_service

      expect(
        PaymentProviders::StripeProvider::CreatePayment
      ).to have_received(:new)
        .with(payment: payment)

      expect(stripe_provider)
        .to have_received(:call)
    end
  end
end
