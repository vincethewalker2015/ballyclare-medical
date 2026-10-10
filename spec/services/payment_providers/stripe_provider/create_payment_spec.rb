
require "rails_helper"

RSpec.describe PaymentProviders::StripeProvider::CreatePayment do
  let(:payment) do
    instance_double(
      Payment,
      id: "payment-123",
      amount_cents: 5000,
      currency: "GBP",
      idempotency_key: "idempotency-123",
      appointment_hold_id: "hold-123",
      appointment_id: nil,
      provider_payment_id: nil,
      status: "pending"
    )
  end

  let(:payment_intent) do
    instance_double(
      Stripe::PaymentIntent,
      id: "pi_test_123"
    )
  end

  describe "#call" do
    before do
    allow(payment)
      .to receive(:with_lock)
      .and_yield
  end
    it "creates a Stripe PaymentIntent with the correct details" do
      expect(Stripe::PaymentIntent)
        .to receive(:create)
        .with(
          {
            amount: 5000,
            currency: "gbp",
            metadata: {
              payment_id: "payment-123",
              appointment_hold_id: "hold-123",
              appointment_id: nil
            }
          },
          {
            idempotency_key: "idempotency-123"
          }
        )
        .and_return(payment_intent)

      allow(payment)
        .to receive(:update!)
        .with(
          provider_payment_id: "pi_test_123",
          status: "processing"
        )

      described_class.new(payment: payment).call
    end

    it "stores the Stripe PaymentIntent ID and marks the payment as processing" do
      allow(Stripe::PaymentIntent)
        .to receive(:create)
        .and_return(payment_intent)

      expect(payment)
        .to receive(:update!)
        .with(
          provider_payment_id: "pi_test_123",
          status: "processing"
        )

      described_class.new(payment: payment).call
    end

    it "does not update the payment when Stripe fails" do
      allow(Stripe::PaymentIntent)
        .to receive(:create)
        .and_raise(
          Stripe::APIConnectionError.new("Stripe is unavailable")
        )

      expect(payment).not_to receive(:update!)

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(Stripe::APIConnectionError)
    end

    it "includes the appointment ID for an existing appointment payment" do
      appointment = create(:appointment)

      allow(payment)
        .to receive(:appointment_hold_id)
        .and_return(nil)

      allow(payment)
        .to receive(:appointment_id)
        .and_return(appointment.id)

      expect(Stripe::PaymentIntent)
        .to receive(:create)
        .with(
          {
            amount: 5000,
            currency: "gbp",
            metadata: {
              payment_id: "payment-123",
              appointment_hold_id: nil,
              appointment_id: appointment.id
            }
          },
          {
            idempotency_key: "idempotency-123"
          }
        )
        .and_return(payment_intent)

      allow(payment)
        .to receive(:with_lock)
        .and_yield

      allow(payment)
        .to receive(:update!)

      described_class.new(payment: payment).call
    end

    it "locks the appointment before updating an existing appointment payment" do
      appointment = create(:appointment)

      allow(payment)
        .to receive(:appointment_hold_id)
        .and_return(nil)

      allow(payment)
        .to receive(:appointment_id)
        .and_return(appointment.id)

      allow(Stripe::PaymentIntent)
        .to receive(:create)
        .and_return(payment_intent)

      expect(appointment)
        .to receive(:with_lock)
        .ordered
        .and_call_original

      expect(payment)
        .to receive(:with_lock)
        .ordered
        .and_yield

      allow(payment)
        .to receive(:update!)

      allow(Appointment)
        .to receive(:find)
        .with(appointment.id)
        .and_return(appointment)

      described_class.new(payment: payment).call
    end

    it "does not overwrite a payment completed by a webhook" do
      appointment = create(:appointment)

      appointment_payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: nil,
        status: "pending",
        amount_cents: 5000,
        currency: appointment.practice.currency
      )

      allow(Stripe::PaymentIntent)
        .to receive(:create) do
          # Simulate the webhook completing payment before
          # the Stripe API request returns.
          appointment_payment.update!(
            provider_payment_id: "pi_test_123",
            status: "succeeded",
            paid_at: Time.current
          )

          payment_intent
        end

      described_class.new(payment: appointment_payment).call

      expect(appointment_payment.reload).to have_attributes(
        provider_payment_id: "pi_test_123",
        status: "succeeded"
      )

      expect(appointment_payment.paid_at).to be_present
    end

    it "does not overwrite a different Stripe PaymentIntent ID" do
      appointment = create(:appointment)

      appointment_payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: nil,
        status: "pending",
        amount_cents: 5000,
        currency: appointment.practice.currency
      )

      allow(Stripe::PaymentIntent)
        .to receive(:create) do
          appointment_payment.update!(
            provider_payment_id: "pi_different_456",
            status: "succeeded",
            paid_at: Time.current
          )

          payment_intent
        end

      expect {
        described_class.new(payment: appointment_payment).call
      }.to raise_error(
        RuntimeError,
        /different Stripe PaymentIntent/
      )

      expect(appointment_payment.reload).to have_attributes(
        provider_payment_id: "pi_different_456",
        status: "succeeded"
      )
    end

    it "does not overwrite a completed appointment-hold payment" do
      hold = create(:appointment_hold)

      hold_payment = create(
        :payment,
        appointment: nil,
        appointment_hold: hold,
        patient: hold.patient,
        provider: "stripe",
        provider_payment_id: nil,
        status: "pending",
        amount_cents: 5000,
        currency: hold.appointment_slot.practice.currency
      )

      # Ensure this test exercises the appointment-hold branch.
      expect(hold_payment.appointment_id).to be_nil
      expect(hold_payment.appointment_hold_id).to be_present

      allow(Stripe::PaymentIntent)
        .to receive(:create) do
          # Simulate the webhook completing payment before
          # the Stripe API request returns.
          hold_payment.update!(
            provider_payment_id: "pi_test_123",
            status: "succeeded",
            paid_at: Time.current
          )

          payment_intent
        end

      described_class.new(payment: hold_payment).call

      expect(hold_payment.reload).to have_attributes(
        provider_payment_id: "pi_test_123",
        status: "succeeded"
      )

      expect(hold_payment.paid_at).to be_present
    end
  end
end
