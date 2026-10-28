require "rails_helper"

RSpec.describe ReconcileProcessingRefundsJob, type: :job do
  describe "#perform" do
    it "reconciles a successful Stripe refund without an appointment" do
      payment = create(:payment,
        appointment: nil,
        patient: create(:patient),
        status: "requires_refund",
        provider: "stripe",
        provider_payment_id: "pi_expired_patient_hold",
        amount_cents: 4000,
        currency: "GBP")

      refund = create(:refund,
        payment: payment,
        amount_cents: 4000,
        currency: "GBP",
        status: "processing",
        provider_refund_id: "re_expired_patient_hold")
      refund.update_columns(updated_at: 20.minutes.ago)

      stripe_refund = Stripe::Refund.construct_from(
        id: "re_expired_patient_hold",
        object: "refund",
        amount: 4000,
        currency: "gbp",
        status: "succeeded",
        payment_intent: "pi_expired_patient_hold"
      )

      expect(Stripe::Refund).to receive(:retrieve)
        .with("re_expired_patient_hold")
        .and_return(stripe_refund)
      expect(Stripe::Refund).not_to receive(:create)

      described_class.perform_now

      expect(refund.reload.status).to eq("succeeded")
      expect(refund.refunded_at).to be_present
      expect(payment.reload.appointment_id).to be_nil
    end

    it "reconciles a processing refund older than 15 minutes" do
      payment = create(
        :payment,
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_old_refund",
        amount_cents: 5000,
        currency: "GBP",
        paid_at: Time.current
      )

      refund = create(
        :refund,
        payment: payment,
        amount_cents: 5000,
        currency: "GBP",
        status: "processing",
        provider_refund_id: "re_old_refund"
      )

      refund.update_columns(
        updated_at: 20.minutes.ago
      )

      reconciliation = instance_double(
        Payments::ReconcileRefund
      )

      expect(Payments::ReconcileRefund)
        .to receive(:new)
        .with(refund: have_attributes(id: refund.id))
        .and_return(reconciliation)

      expect(reconciliation).to receive(:call).once

      described_class.new.perform
    end

    it "continues reconciling other refunds when one fails" do
      payment = create(
        :payment,
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_batch_test",
        amount_cents: 10000,
        currency: "GBP",
        paid_at: Time.current
      )

      failed_refund = create(
        :refund,
        payment: payment,
        amount_cents: 5000,
        currency: "GBP",
        status: "processing",
        provider_refund_id: "re_batch_failed"
      )

      successful_refund = create(
        :refund,
        payment: payment,
        amount_cents: 5000,
        currency: "GBP",
        status: "processing",
        provider_refund_id: "re_batch_success"
      )

      [ failed_refund, successful_refund ].each do |refund|
        refund.update_columns(updated_at: 20.minutes.ago)
      end

      attempted_ids = []

      allow(Payments::ReconcileRefund).to receive(:new) do |refund:|
        attempted_ids << refund.id

        reconciliation = instance_double(Payments::ReconcileRefund)

        if refund.id == failed_refund.id
          allow(reconciliation).to receive(:call)
            .and_raise(Stripe::APIConnectionError.new("Connection lost"))
        else
          allow(reconciliation).to receive(:call).and_return(refund)
        end

        reconciliation
      end

      expect {
        described_class.new.perform
      }.not_to raise_error

      expect(attempted_ids).to contain_exactly(
        failed_refund.id,
        successful_refund.id
      )

      expect(failed_refund.reload.status).to eq("processing")
      expect(successful_refund.reload.status).to eq("processing")
    end

    it "does not reconcile a recently updated processing refund" do
      payment = create(
        :payment,
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_recent_refund",
        amount_cents: 5000,
        currency: "GBP",
        paid_at: Time.current
      )

      refund = create(
        :refund,
        payment: payment,
        amount_cents: 5000,
        currency: "GBP",
        status: "processing",
        provider_refund_id: "re_recent_refund"
      )

      refund.update_columns(
        updated_at: 5.minutes.ago
      )

      expect(Payments::ReconcileRefund).not_to receive(:new)

      described_class.new.perform

      expect(refund.reload.status).to eq("processing")
      expect(refund.provider_refund_id).to eq("re_recent_refund")
    end

    it "does not reconcile an already succeeded refund" do
      payment = create(
        :payment,
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_completed_refund",
        amount_cents: 5000,
        currency: "GBP",
        paid_at: Time.current
      )

      refund = create(
        :refund,
        payment: payment,
        amount_cents: 5000,
        currency: "GBP",
        status: "succeeded",
        provider_refund_id: "re_completed_refund",
        refunded_at: 1.hour.ago
      )

      refund.update_columns(
        updated_at: 1.hour.ago
      )

      expect(Payments::ReconcileRefund).not_to receive(:new)

      described_class.new.perform

      expect(refund.reload.status).to eq("succeeded")
      expect(refund.provider_refund_id).to eq("re_completed_refund")
    end

    it "waits before checking a refund again after reconciliation" do
      payment = create(
        :payment,
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_recheck",
        amount_cents: 5000,
        currency: "GBP",
        paid_at: Time.current
      )

      refund = create(
        :refund,
        payment: payment,
        amount_cents: 5000,
        currency: "GBP",
        status: "processing",
        provider_refund_id: "re_recheck"
      )

      refund.update_columns(updated_at: 20.minutes.ago)

      reconciliation = instance_double(Payments::ReconcileRefund)

      allow(Payments::ReconcileRefund)
        .to receive(:new)
        .and_return(reconciliation)

      allow(reconciliation).to receive(:call).and_return(refund)

      described_class.new.perform
      described_class.new.perform

      expect(reconciliation).to have_received(:call).once
      expect(refund.reload.status).to eq("processing")
    end

    it "skips a refund locked by another reconciliation worker" do
      payment = create(
        :payment,
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_locked_reconciliation",
        amount_cents: 5000,
        currency: "GBP",
        paid_at: Time.current
      )

      refund = create(
        :refund,
        payment: payment,
        amount_cents: 5000,
        currency: "GBP",
        status: "processing",
        provider_refund_id: "re_locked_reconciliation"
      )

      refund.update_columns(updated_at: 20.minutes.ago)

      lock_key = Zlib.crc32("refund-reconciliation:#{refund.id}")

      primary_connection = ActiveRecord::Base.connection

      connection_options =
        primary_connection.raw_connection.conninfo_hash.reject do |_key, value|
          value.nil? || value == ""
        end

      other_connection = PG.connect(connection_options)
      lock_acquired = false

      begin
        expect(other_connection.backend_pid).not_to eq(
          primary_connection.raw_connection.backend_pid
        )

        lock_acquired = other_connection.exec_params(
          "SELECT pg_try_advisory_lock($1)",
          [ lock_key ]
        ).getvalue(0, 0) == "t"

        expect(lock_acquired).to be(true)

        expect(Payments::ReconcileRefund).not_to receive(:new)

        described_class.new.perform

        expect(refund.reload.status).to eq("processing")
        expect(refund.updated_at).to be < 15.minutes.ago
      ensure
        if lock_acquired
          other_connection.exec_params(
            "SELECT pg_advisory_unlock($1)",
            [ lock_key ]
          )
        end

        other_connection.close
      end
    end

    it "releases the advisory lock when reconciliation raises an error" do
      payment = create(
        :payment,
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_reconciliation_error",
        amount_cents: 5000,
        currency: "GBP",
        paid_at: Time.current
      )

      refund = create(
        :refund,
        payment: payment,
        amount_cents: 5000,
        currency: "GBP",
        status: "processing",
        provider_refund_id: "re_reconciliation_error"
      )

      refund.update_columns(updated_at: 20.minutes.ago)

      reconciliation = instance_double(Payments::ReconcileRefund)

      allow(Payments::ReconcileRefund)
        .to receive(:new)
        .and_return(reconciliation)

      allow(reconciliation)
        .to receive(:call)
        .and_raise(Stripe::APIConnectionError.new("Connection lost"))

      expect {
        described_class.new.perform
      }.not_to raise_error

      lock_key = Zlib.crc32("refund-reconciliation:#{refund.id}")

      primary_connection = ActiveRecord::Base.connection

      connection_options =
        primary_connection.raw_connection.conninfo_hash.reject do |_key, value|
          value.nil? || value == ""
        end

      other_connection = PG.connect(connection_options)
      lock_acquired = false

      begin
        lock_acquired = other_connection.exec_params(
          "SELECT pg_try_advisory_lock($1)",
          [ lock_key ]
        ).getvalue(0, 0) == "t"

        expect(lock_acquired).to be(true)
        expect(refund.reload.status).to eq("processing")
        expect(refund.updated_at).to be < 15.minutes.ago
      ensure
        if lock_acquired
          other_connection.exec_params(
            "SELECT pg_advisory_unlock($1)",
            [ lock_key ]
          )
        end

        other_connection.close
      end
    end
  end
end
