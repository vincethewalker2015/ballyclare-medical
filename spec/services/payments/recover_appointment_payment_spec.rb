require "rails_helper"
RSpec.describe Payments::RecoverAppointmentPayment do
  describe "#call" do
    it "recovers a recent pending payment using its original Stripe idempotency key" do
      appointment = create(:appointment)
      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: nil,
        status: "pending",
        idempotency_key: SecureRandom.uuid
      )
      payment_intent = double(
        id: "pi_recovered",
        status: "requires_payment_method"
      )
      expect(Stripe::PaymentIntent)
        .to receive(:create)
        .with(
          {
            amount: payment.amount_cents,
            currency: payment.currency.downcase,
            metadata: {
              payment_id: payment.id,
              appointment_hold_id: payment.appointment_hold_id,
              appointment_id: payment.appointment_id
            }
          },
          {
            idempotency_key: payment.idempotency_key
          }
        )
        .and_return(payment_intent)
      result = described_class.new(payment: payment).call
      expect(result.id).to eq("pi_recovered")
      expect(payment.reload.provider_payment_id).to eq("pi_recovered")
      expect(payment.status).to eq("processing")
    end
    it "rejects a payment older than the recovery window without contacting Stripe" do
      appointment = create(:appointment)
      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: nil,
        status: "pending",
        idempotency_key: SecureRandom.uuid,
        created_at: 13.hours.ago
      )
      expect(Stripe::PaymentIntent)
        .not_to receive(:create)
      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        Payments::RecoverAppointmentPayment::PaymentNotRecoverable
      )
      expect(payment.reload.status).to eq("pending")
      expect(payment.provider_payment_id).to be_nil
    end
    it "rejects recovery for a cancelled appointment without contacting Stripe" do
      appointment = create(:appointment, status: "cancelled")
      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: nil,
        status: "pending",
        idempotency_key: SecureRandom.uuid
      )
      expect(Stripe::PaymentIntent)
        .not_to receive(:create)
      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        Payments::RecoverAppointmentPayment::PaymentNotRecoverable
      )
      expect(payment.reload.status).to eq("pending")
      expect(payment.provider_payment_id).to be_nil
    end
    it "does not overwrite a payment that succeeds during Stripe recovery" do
      appointment = create(:appointment)
      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: nil,
        status: "pending",
        idempotency_key: SecureRandom.uuid
      )
      allow(Stripe::PaymentIntent)
        .to receive(:create) do
          # Simulate a successful webhook arriving while
          # the recovery request is in progress.
          payment.update!(
            status: "succeeded",
            provider_payment_id: "pi_webhook"
          )
          double(
            id: "pi_recovered",
            status: "requires_payment_method"
          )
        end
      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        Payments::RecoverAppointmentPayment::PaymentNotRecoverable
      )
      expect(payment.reload.status).to eq("succeeded")
      expect(payment.provider_payment_id).to eq("pi_webhook")
    end
    it "rejects recovery when the payment succeeds with the same PaymentIntent ID" do
      appointment = create(:appointment)
      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: nil,
        status: "pending",
        idempotency_key: SecureRandom.uuid
      )
      allow(Stripe::PaymentIntent)
        .to receive(:create) do
          # Simulate a webhook recording a successful payment
          # while Stripe recovery is in progress.
          payment.update!(
            status: "succeeded",
            provider_payment_id: "pi_recovered"
          )
          double(
            id: "pi_recovered",
            status: "succeeded"
          )
        end
      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        Payments::RecoverAppointmentPayment::PaymentNotRecoverable
      )
      expect(payment.reload.status).to eq("succeeded")
      expect(payment.provider_payment_id).to eq("pi_recovered")
    end
    it "rejects an already successful payment without contacting Stripe" do
      appointment = create(:appointment)
      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: "pi_paid",
        status: "succeeded",
        idempotency_key: SecureRandom.uuid
      )
      expect(Stripe::PaymentIntent)
        .not_to receive(:create)
      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        Payments::RecoverAppointmentPayment::PaymentNotRecoverable
      )
      expect(payment.reload.status).to eq("succeeded")
      expect(payment.provider_payment_id).to eq("pi_paid")
    end
    it "rejects recovery when another request holds the recovery lock" do
      appointment = create(:appointment)
      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: nil,
        status: "pending",
        idempotency_key: SecureRandom.uuid
      )
      connection = ActiveRecord::Base.connection
      allow(connection)
        .to receive(:select_value)
        .and_call_original
      expect(connection)
        .to receive(:select_value)
        .with(a_string_including("pg_try_advisory_lock"))
        .and_return(false)
      expect(Stripe::PaymentIntent)
        .not_to receive(:create)
      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        Payments::RecoverAppointmentPayment::PaymentNotRecoverable
      )
      expect(payment.reload.status).to eq("pending")
      expect(payment.provider_payment_id).to be_nil
    end
    it "releases the recovery lock when Stripe raises an error" do
      appointment = create(:appointment)
      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: nil,
        status: "pending",
        idempotency_key: SecureRandom.uuid
      )
      allow(Stripe::PaymentIntent)
        .to receive(:create)
        .and_raise(
          Stripe::APIConnectionError.new("Stripe connection failed")
        )
      expect {
        described_class.new(payment: payment).call
      }.to raise_error(Stripe::APIConnectionError)
      lock_key = Zlib.crc32("payment-recovery:#{payment.id}")
      connection = ActiveRecord::Base.connection
      acquired = connection.select_value(
        "SELECT pg_try_advisory_lock(#{lock_key})"
      )
      expect(acquired).to eq(true)
      connection.select_value(
        "SELECT pg_advisory_unlock(#{lock_key})"
      )
      expect(payment.reload.status).to eq("pending")
    end
    it "releases its advisory lock so another database connection can acquire it" do
      appointment = create(:appointment)
      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: nil,
        status: "pending",
        idempotency_key: SecureRandom.uuid
      )
      allow(Stripe::PaymentIntent)
        .to receive(:create)
        .and_raise(
          Stripe::APIConnectionError.new("Stripe connection failed")
        )
      expect {
        described_class.new(payment: payment).call
      }.to raise_error(Stripe::APIConnectionError)
      lock_key = Zlib.crc32("payment-recovery:#{payment.id}")
      pool = ActiveRecord::Base.connection_pool
      recovery_pid = ActiveRecord::Base.connection.raw_connection.backend_pid
      second_connection = pool.checkout
      begin
        acquired = second_connection.select_value(
          "SELECT pg_try_advisory_lock(#{lock_key})"
        )
        expect(acquired).to eq(true)
      ensure
        second_connection.select_value(
          "SELECT pg_advisory_unlock(#{lock_key})"
        ) if acquired
        pool.checkin(second_connection)
      end
      expect(payment.reload.status).to eq("pending")
    end
  end
end
