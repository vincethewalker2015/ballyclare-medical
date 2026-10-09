require "rails_helper"

RSpec.describe Payments::HandleSucceeded do
  let(:appointment_slot) { create(:appointment_slot) }

  let(:patient) do
    create(
      :patient,
      practice: appointment_slot.practice
    )
  end

  let(:appointment_hold) do
    appointment_slot.hold_for!(
      patient: patient
    )
  end

  let!(:payment) do
    Payment.create!(
      appointment_hold: appointment_hold,
      patient: patient,
      provider: "stripe",
      provider_payment_id: "pi_test_123",
      amount_cents: 5000,
      currency: appointment_slot.practice.currency,
      status: "processing",
      idempotency_key: SecureRandom.uuid
    )
  end

  let(:payment_intent) do
    instance_double(
      Stripe::PaymentIntent,
      id: "pi_test_123",
      amount_received: 5000,
      currency: appointment_slot.practice.currency.downcase
    )
  end

  describe "#call" do
    context "when the payment belongs to an appointment hold" do
      it "marks the payment as succeeded and completes the booking" do
        described_class.new(
          payment_intent: payment_intent
        ).call

        payment.reload

        expect(payment.status).to eq("succeeded")
        expect(payment.paid_at).to be_present

        expect(payment.appointment).to be_present
        expect(payment.appointment_hold).to be_nil

        expect(payment.appointment.patient).to eq(patient)
        expect(payment.appointment.appointment_slot).to eq(appointment_slot)

        expect {
          appointment_hold.reload
        }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it "completes the booking when the payment is already succeeded" do
        payment.update!(
          status: "succeeded",
          paid_at: 5.minutes.ago
        )

        original_paid_at = payment.paid_at

        booking_service = instance_double(
          Payments::CompleteBooking
        )

        expect(Payments::CompleteBooking)
          .to receive(:new)
          .with(payment: payment)
          .and_return(booking_service)

        expect(booking_service)
          .to receive(:call)

        described_class.new(
          payment_intent: payment_intent
        ).call

        payment.reload

        expect(payment.status).to eq("succeeded")
        expect(payment.paid_at).to eq(original_paid_at)
      end

      it "rejects an amount mismatch" do
        allow(payment_intent)
          .to receive(:amount_received)
          .and_return(4000)

        expect {
          described_class.new(
            payment_intent: payment_intent
          ).call
        }.to raise_error(
          Payments::HandleSucceeded::AmountMismatch
        )

        expect(payment.reload.status).to eq("processing")
      end

      it "rejects a currency mismatch" do
        allow(payment_intent)
          .to receive(:currency)
          .and_return("usd")

        expect {
          described_class.new(
            payment_intent: payment_intent
          ).call
        }.to raise_error(
          Payments::HandleSucceeded::CurrencyMismatch
        )

        expect(payment.reload.status).to eq("processing")
      end

      it "raises when the local payment cannot be found" do
        allow(payment_intent)
          .to receive(:id)
          .and_return("pi_unknown")

        expect {
          described_class.new(
            payment_intent: payment_intent
          ).call
        }.to raise_error(
          Payments::HandleSucceeded::PaymentNotFound
        )
      end

      it "completes the booking after marking the payment as succeeded" do
        booking_service = instance_double(
          Payments::CompleteBooking
        )

        expect(Payments::CompleteBooking)
          .to receive(:new)
          .with(payment: payment)
          .and_return(booking_service)

        expect(booking_service)
          .to receive(:call)

        described_class.new(
          payment_intent: payment_intent
        ).call

        expect(payment.reload.status).to eq("succeeded")
        expect(payment.paid_at).to be_present
      end

      it "marks the payment as requiring a refund when the slot is unavailable" do
        booking_service = instance_double(
          Payments::CompleteBooking
        )

        allow(Payments::CompleteBooking)
          .to receive(:new)
          .with(payment: payment)
          .and_return(booking_service)

        allow(booking_service)
          .to receive(:call)
          .and_raise(
            Payments::CompleteBooking::SlotUnavailable,
            "Appointment slot has already been booked"
          )

        described_class.new(
          payment_intent: payment_intent
        ).call

        payment.reload

        expect(payment.status).to eq("requires_refund")
        expect(payment.paid_at).to be_present
      end

      it "marks the payment as requiring a refund when the hold has expired" do
        booking_service = instance_double(
          Payments::CompleteBooking
        )

        allow(Payments::CompleteBooking)
          .to receive(:new)
          .with(payment: payment)
          .and_return(booking_service)

        allow(booking_service)
          .to receive(:call)
          .and_raise(
            Payments::CompleteBooking::HoldExpired,
            "Appointment hold has expired"
          )

        described_class.new(
          payment_intent: payment_intent
        ).call

        payment.reload

        expect(payment.status).to eq("requires_refund")
        expect(payment.paid_at).to be_present
      end

      it "does not retry booking when payment already requires a refund" do
        payment.update!(
          status: "requires_refund",
          paid_at: 5.minutes.ago
        )

        expect(Payments::CompleteBooking)
          .not_to receive(:new)

        result = described_class.new(
          payment_intent: payment_intent
        ).call

        expect(result.status).to eq("requires_refund")
        expect(result.paid_at).to eq(payment.paid_at)
      end
    end

    context "when the payment belongs to an existing appointment" do
      let(:existing_appointment) do
        create(
          :appointment,
          practice: appointment_slot.practice,
          appointment_slot: appointment_slot,
          patient: patient,
          clinician: appointment_slot.clinician
        )
      end

      let!(:appointment_charge) do
        create(
          :appointment_charge,
          appointment: existing_appointment,
          patient: patient,
          practice: appointment_slot.practice,
          amount_cents: 5000,
          status: "active"
        )
      end

      let!(:payment) do
        Payment.create!(
          appointment: existing_appointment,
          appointment_hold: nil,
          patient: patient,
          provider: "stripe",
          provider_payment_id: "pi_test_123",
          amount_cents: 5000,
          currency: appointment_slot.practice.currency,
          status: "processing",
          idempotency_key: SecureRandom.uuid
        )
      end

      let(:payment_intent) do
        instance_double(
          Stripe::PaymentIntent,
          id: "pi_test_123",
          amount_received: 5000,
          currency: appointment_slot.practice.currency.downcase
        )
      end

      it "marks the appointment payment as succeeded" do
        described_class.new(
          payment_intent: payment_intent
        ).call

        payment.reload

        expect(payment.status).to eq("succeeded")
        expect(payment.paid_at).to be_present
        expect(payment.appointment).to eq(existing_appointment)
        expect(payment.appointment_hold).to be_nil
      end

      it "does not attempt to complete another booking" do
        expect(Payments::CompleteBooking)
          .not_to receive(:new)

        described_class.new(
          payment_intent: payment_intent
        ).call

        expect(existing_appointment.reload).to be_present
      end

      it "reduces the appointment balance" do
        expect {
          described_class.new(
            payment_intent: payment_intent
          ).call
        }.to change {
          Billing::AppointmentBalance.new(
            appointment: existing_appointment
          ).call[:balance_cents]
        }.from(5000).to(0)
      end

      it "handles a repeated success event without changing the payment again" do
        handler = described_class.new(
          payment_intent: payment_intent
        )

        handler.call

        original_paid_at = payment.reload.paid_at

        balance_after_first_event = Billing::AppointmentBalance.new(
          appointment: existing_appointment
        ).call[:balance_cents]

        handler.call

        expect(payment.reload.status).to eq("succeeded")
        expect(payment.paid_at).to eq(original_paid_at)

        expect(
          Billing::AppointmentBalance.new(
            appointment: existing_appointment
          ).call[:balance_cents]
        ).to eq(balance_after_first_event)
      end
    end
  end
end
