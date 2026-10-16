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

    it "does not credit a Stripe success with the wrong amount" do
      appointment = create(:appointment)
      create(:appointment_charge, appointment: appointment)

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: "pi_wrong_amount",
        amount_cents: 5000,
        currency: appointment.practice.currency,
        status: "processing"
      )
      payment.update_columns(updated_at: 20.minutes.ago)

      payment_intent = instance_double(
        Stripe::PaymentIntent,
        id: "pi_wrong_amount",
        status: "succeeded",
        amount_received: 4000,
        currency: appointment.practice.currency.downcase
      )

      expect(Stripe::PaymentIntent)
        .to receive(:retrieve)
        .with("pi_wrong_amount")
        .and_return(payment_intent)

      described_class.new.perform

      expect(payment.reload.status).to eq("processing")
      expect(payment.paid_at).to be_nil
      expect(
        Billing::AppointmentBalance.new(appointment: appointment).call[:balance_cents]
      ).to eq(5000)
    end

    it "does not reconcile a recently updated processing payment" do
      appointment = create(:appointment)
      create(:appointment_charge, appointment: appointment)

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: "pi_recent_payment",
        amount_cents: 5000,
        currency: appointment.practice.currency,
        status: "processing"
      )
      payment.update_columns(updated_at: 5.minutes.ago)

      expect(Stripe::PaymentIntent).not_to receive(:retrieve)

      described_class.new.perform

      expect(payment.reload.status).to eq("processing")
      expect(payment.paid_at).to be_nil
    end

    it "releases a processing payment when Stripe confirms cancellation" do
      appointment = create(:appointment)
      create(:appointment_charge, appointment: appointment)

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: "pi_cancelled_elsewhere",
        amount_cents: 5000,
        currency: appointment.practice.currency,
        status: "processing"
      )
      payment.update_columns(updated_at: 20.minutes.ago)

      payment_intent = instance_double(
        Stripe::PaymentIntent,
        id: "pi_cancelled_elsewhere",
        status: "canceled"
      )

      expect(Stripe::PaymentIntent)
        .to receive(:retrieve)
        .twice
        .with("pi_cancelled_elsewhere")
        .and_return(payment_intent)

      described_class.new.perform

      expect(payment.reload.status).to eq("cancelled")
      expect(payment.paid_at).to be_nil
      expect(
        Billing::AppointmentBalance.new(appointment: appointment).call[:balance_cents]
      ).to eq(5000)
    end

    it "does not credit a successful Stripe payment in the wrong currency" do
      appointment = create(:appointment)
      create(:appointment_charge, appointment: appointment)

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: "pi_wrong_currency",
        amount_cents: 5000,
        currency: appointment.practice.currency,
        status: "processing"
      )
      payment.update_columns(updated_at: 20.minutes.ago)

      other_currency = appointment.practice.currency.casecmp?("USD") ? "EUR" : "USD"

      payment_intent = instance_double(
        Stripe::PaymentIntent,
        id: "pi_wrong_currency",
        status: "succeeded",
        amount_received: 5000,
        currency: other_currency.downcase
      )

      expect(Stripe::PaymentIntent)
        .to receive(:retrieve)
        .with("pi_wrong_currency")
        .and_return(payment_intent)

      described_class.new.perform

      expect(payment.reload.status).to eq("processing")
      expect(payment.paid_at).to be_nil
      expect(
        Billing::AppointmentBalance.new(appointment: appointment).call[:balance_cents]
      ).to eq(5000)
    end

    it "continues reconciling other payments when Stripe fails for one" do
      appointment = create(:appointment)
      create(:appointment_charge, appointment: appointment)

      unavailable_payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider_payment_id: "pi_unavailable",
        status: "processing"
      )

      recovered_payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider_payment_id: "pi_recovered",
        status: "processing"
      )

      [unavailable_payment, recovered_payment].each do |payment|
        payment.update_columns(updated_at: 20.minutes.ago)
      end

      allow(Stripe::PaymentIntent)
        .to receive(:retrieve)
        .with("pi_unavailable")
        .and_raise(Stripe::APIConnectionError.new("Connection lost"))

      allow(Stripe::PaymentIntent)
        .to receive(:retrieve)
        .with("pi_recovered")
        .and_return(
          instance_double(
            Stripe::PaymentIntent,
            id: "pi_recovered",
            status: "succeeded",
            amount_received: 5000,
            currency: appointment.practice.currency.downcase
          )
        )

      expect { described_class.new.perform }.not_to raise_error

      expect(unavailable_payment.reload.status).to eq("processing")
      expect(recovered_payment.reload.status).to eq("succeeded")
    end
  end
end
