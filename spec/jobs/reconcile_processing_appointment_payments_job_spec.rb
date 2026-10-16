require "rails_helper"

RSpec.describe ReconcileProcessingAppointmentPaymentsJob, type: :job do
  describe "#perform" do
    it "records a successful Stripe payment when its webhook was missed" do
      appointment = create(:appointment)

      create(
        :appointment_charge,
        appointment: appointment,
        patient: appointment.patient,
        practice: appointment.practice,
        amount_cents: 5000,
        status: "active"
      )

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: "pi_missed_webhook",
        amount_cents: 5000,
        currency: appointment.practice.currency,
        status: "processing"
      )
      payment.update_columns(updated_at: 20.minutes.ago)

      payment_intent = instance_double(
        Stripe::PaymentIntent,
        id: "pi_missed_webhook",
        status: "succeeded",
        amount_received: 5000,
        currency: appointment.practice.currency.downcase
      )

      expect(Stripe::PaymentIntent)
        .to receive(:retrieve)
        .with("pi_missed_webhook")
        .and_return(payment_intent)

      described_class.new.perform

      expect(payment.reload.status).to eq("succeeded")
      expect(payment.paid_at).to be_present
      expect(
        Billing::AppointmentBalance.new(appointment: appointment).call[:balance_cents]
      ).to eq(0)
    end

    it "does not mark an unsuccessful Stripe payment as paid" do
      appointment = create(:appointment)
      create(:appointment_charge, appointment: appointment)

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: "pi_still_processing",
        amount_cents: 5000,
        currency: appointment.practice.currency,
        status: "processing"
      )
      payment.update_columns(updated_at: 20.minutes.ago)

      payment_intent = instance_double(
        Stripe::PaymentIntent,
        id: "pi_still_processing",
        status: "processing"
      )

      expect(Stripe::PaymentIntent)
        .to receive(:retrieve)
        .with("pi_still_processing")
        .and_return(payment_intent)

      described_class.new.perform

      expect(payment.reload.status).to eq("processing")
      expect(payment.paid_at).to be_nil
      expect(
        Billing::AppointmentBalance.new(appointment: appointment).call[:balance_cents]
      ).to eq(5000)
    end
  end
end
