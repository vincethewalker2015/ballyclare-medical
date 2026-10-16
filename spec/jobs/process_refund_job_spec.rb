require "rails_helper"

RSpec.describe ProcessRefundJob, type: :job do
  describe "#perform" do
    it "does not submit an already processing refund to Stripe" do
      payment = create(
        :payment,
        status: "succeeded",
        provider_payment_id: "pi_existing_123",
        paid_at: Time.current
      )

      refund = create(
        :refund,
        payment: payment,
        status: "processing",
        provider_refund_id: "re_existing_123"
      )

      expect(
        PaymentProviders::StripeProvider::CreateRefund
      ).not_to receive(:new)

      described_class.new.perform(refund.id)

      expect(refund.reload.status).to eq("processing")
      expect(refund.provider_refund_id).to eq("re_existing_123")
    end

    it "submits a pending refund through the Stripe provider" do
      payment = create(
        :payment,
        status: "succeeded",
        provider_payment_id: "pi_existing_456",
        paid_at: Time.current
      )

      refund = create(
        :refund,
        payment: payment,
        status: "pending"
      )

      stripe_service = instance_double(
        PaymentProviders::StripeProvider::CreateRefund
      )

      expect(
        PaymentProviders::StripeProvider::CreateRefund
      ).to receive(:new).with(
        refund: have_attributes(id: refund.id)
      ).and_return(stripe_service)

      expect(stripe_service).to receive(:call).once

      described_class.new.perform(refund.id)
    end

    it "does not submit a refund that another worker has already claimed" do
      payment = create(
        :payment,
        status: "succeeded",
        provider_payment_id: "pi_existing_789",
        paid_at: Time.current
      )

      refund = create(
        :refund,
        payment: payment,
        status: "pending"
      )

      stripe_service = instance_double(
        PaymentProviders::StripeProvider::CreateRefund
      )

      allow(
        PaymentProviders::StripeProvider::CreateRefund
      ).to receive(:new).and_return(stripe_service)

      allow(stripe_service).to receive(:call) do
        refund.update!(status: "processing")
      end

      described_class.new.perform(refund.id)
      described_class.new.perform(refund.id)

      expect(
        PaymentProviders::StripeProvider::CreateRefund
      ).to have_received(:new).once
    end

    it "does not submit a refund while another worker holds its advisory lock" do
      payment = create(
        :payment,
        status: "succeeded",
        provider_payment_id: "pi_locked_123",
        paid_at: Time.current
      )

      refund = create(
        :refund,
        payment: payment,
        status: "pending"
      )

      lock_key = Zlib.crc32("refund-processing:#{refund.id}")

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

        lock_acquired = other_connection
          .exec_params(
            "SELECT pg_try_advisory_lock($1)",
            [ lock_key ]
          )
          .getvalue(0, 0) == "t"

        expect(lock_acquired).to be(true)

        expect(
          PaymentProviders::StripeProvider::CreateRefund
        ).not_to receive(:new)

        described_class.new.perform(refund.id)

        expect(refund.reload.status).to eq("pending")
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

    it "releases the advisory lock when Stripe raises an error" do
      payment = create(
        :payment,
        status: "succeeded",
        provider_payment_id: "pi_error_123",
        paid_at: Time.current
      )

      refund = create(
        :refund,
        payment: payment,
        status: "pending"
      )

      stripe_service = instance_double(
        PaymentProviders::StripeProvider::CreateRefund
      )

      allow(
        PaymentProviders::StripeProvider::CreateRefund
      ).to receive(:new).and_return(stripe_service)

      allow(stripe_service).to receive(:call)
        .and_raise(Stripe::APIConnectionError.new("Connection lost"))

      expect {
        described_class.new.perform(refund.id)
      }.to raise_error(Stripe::APIConnectionError)

      lock_key = Zlib.crc32("refund-processing:#{refund.id}")

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
        expect(refund.reload.status).to eq("pending")
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

    it "retries a pending refund after a Stripe connection failure" do
      payment = create(
        :payment,
        status: "succeeded",
        amount_cents: 5000,
        currency: "GBP",
        paid_at: Time.current
      )

      refund = create(
        :refund,
        payment: payment,
        amount_cents: 5000,
        currency: "GBP",
        status: "pending"
      )

      stripe_service = instance_double(
        PaymentProviders::StripeProvider::CreateRefund
      )

      allow(PaymentProviders::StripeProvider::CreateRefund)
        .to receive(:new)
        .with(refund: an_instance_of(Refund))
        .and_return(stripe_service)

      call_count = 0

      allow(stripe_service).to receive(:call) do
        call_count += 1

        if call_count == 1
          raise Stripe::APIConnectionError.new("Connection lost")
        end

        true
      end

      expect {
        described_class.new.perform(refund.id)
      }.to raise_error(Stripe::APIConnectionError)

      expect(refund.reload.status).to eq("pending")

      expect {
        described_class.new.perform(refund.id)
      }.not_to raise_error

      expect(stripe_service).to have_received(:call).twice
    end
  end
end
