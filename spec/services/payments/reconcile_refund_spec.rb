require "rails_helper"

RSpec.describe Payments::ReconcileRefund do
  describe "#call" do
    it "marks a processing refund as succeeded when Stripe confirms success" do
      payment = create(
        :payment,
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_test_123",
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
        provider_refund_id: "re_test_123"
      )

      stripe_refund = Stripe::Refund.construct_from(
        id: "re_test_123",
        object: "refund",
        amount: 5000,
        currency: "gbp",
        status: "succeeded",
        payment_intent: "pi_test_123"
      )

      expect(Stripe::Refund)
        .to receive(:retrieve)
        .with("re_test_123")
        .and_return(stripe_refund)

      result = described_class.new(refund: refund).call

      expect(result.reload.status).to eq("succeeded")
      expect(result.provider_refund_id).to eq("re_test_123")
      expect(result.refunded_at).to be_present
    end

    it "leaves the refund processing when Stripe has not completed it" do
      payment = create(
        :payment,
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_test_456",
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
        provider_refund_id: "re_test_456"
      )

      stripe_refund = Stripe::Refund.construct_from(
        id: "re_test_456",
        object: "refund",
        amount: 5000,
        currency: "gbp",
        status: "pending",
        payment_intent: "pi_test_456"
      )

      expect(Stripe::Refund)
        .to receive(:retrieve)
        .with("re_test_456")
        .and_return(stripe_refund)

      result = described_class.new(refund: refund).call

      expect(result.reload.status).to eq("processing")
      expect(result.provider_refund_id).to eq("re_test_456")
      expect(result.refunded_at).to be_nil
    end

    it "rejects a processing refund without a Stripe refund ID" do
      payment = create(
        :payment,
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_test_789",
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
        provider_refund_id: nil
      )

      expect(Stripe::Refund).not_to receive(:retrieve)

      expect {
        described_class.new(refund: refund).call
      }.to raise_error(
        Payments::ReconcileRefund::MissingProviderRefundId
      )

      expect(refund.reload.status).to eq("processing")
      expect(refund.provider_refund_id).to be_nil
    end

    it "does not contact Stripe for an already succeeded refund" do
      payment = create(
        :payment,
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_test_completed",
        amount_cents: 5000,
        currency: "GBP",
        paid_at: Time.current
      )

      refunded_at = 1.hour.ago

      refund = create(
        :refund,
        payment: payment,
        amount_cents: 5000,
        currency: "GBP",
        status: "succeeded",
        provider_refund_id: "re_test_completed",
        refunded_at: refunded_at
      )

      persisted_refunded_at = refund.reload.refunded_at

      expect(Stripe::Refund).not_to receive(:retrieve)

      result = described_class.new(refund: refund).call

      expect(result.id).to eq(refund.id)
      expect(refund.reload.status).to eq("succeeded")
      expect(refund.refunded_at).to eq(persisted_refunded_at)
    end

    it "preserves the processing refund when Stripe is unavailable" do
      payment = create(
        :payment,
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_test_connection_error",
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
        provider_refund_id: "re_test_connection_error"
      )

      expect(Stripe::Refund)
        .to receive(:retrieve)
        .with("re_test_connection_error")
        .and_raise(
          Stripe::APIConnectionError.new("Connection lost")
        )

      expect {
        described_class.new(refund: refund).call
      }.to raise_error(Stripe::APIConnectionError)

      expect(refund.reload.status).to eq("processing")
      expect(refund.provider_refund_id).to eq("re_test_connection_error")
      expect(refund.refunded_at).to be_nil
    end

    it "marks a processing refund as failed when Stripe confirms failure" do
      payment = create(
        :payment,
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_confirmed_failure",
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
        provider_refund_id: "re_confirmed_failure"
      )

      stripe_refund = Stripe::Refund.construct_from(
        id: "re_confirmed_failure",
        object: "refund",
        amount: 5000,
        currency: "gbp",
        status: "failed",
        payment_intent: "pi_confirmed_failure"
      )

      expect(Stripe::Refund)
        .to receive(:retrieve)
        .with("re_confirmed_failure")
        .and_return(stripe_refund)

      result = described_class.new(refund: refund).call

      expect(result.reload.status).to eq("failed")
      expect(result.provider_refund_id).to eq("re_confirmed_failure")
      expect(result.refunded_at).to be_nil
    end

    it "rejects a failed Stripe refund belonging to another payment" do
      payment = create(
        :payment,
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_correct_payment",
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
        provider_refund_id: "re_wrong_payment"
      )

      stripe_refund = Stripe::Refund.construct_from(
        id: "re_wrong_payment",
        object: "refund",
        amount: 5000,
        currency: "gbp",
        status: "failed",
        payment_intent: "pi_different_payment"
      )

      expect(Stripe::Refund)
        .to receive(:retrieve)
        .with("re_wrong_payment")
        .and_return(stripe_refund)

      expect {
        described_class.new(refund: refund).call
      }.to raise_error(
        Payments::ReconcileRefund::PaymentMismatch
      )

      expect(refund.reload.status).to eq("processing")
      expect(refund.provider_refund_id).to eq("re_wrong_payment")
      expect(refund.refunded_at).to be_nil
    end

    it "rejects a failed Stripe refund with a different amount" do
      payment = create(
        :payment,
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_amount_mismatch",
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
        provider_refund_id: "re_amount_mismatch"
      )

      stripe_refund = Stripe::Refund.construct_from(
        id: "re_amount_mismatch",
        object: "refund",
        amount: 3000,
        currency: "gbp",
        status: "failed",
        payment_intent: "pi_amount_mismatch"
      )

      expect(Stripe::Refund)
        .to receive(:retrieve)
        .with("re_amount_mismatch")
        .and_return(stripe_refund)

      expect {
        described_class.new(refund: refund).call
      }.to raise_error(
        Payments::ReconcileRefund::AmountMismatch
      )

      expect(refund.reload.status).to eq("processing")
      expect(refund.provider_refund_id).to eq("re_amount_mismatch")
      expect(refund.refunded_at).to be_nil
    end

    it "rejects a failed Stripe refund with a different currency" do
      payment = create(
        :payment,
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_currency_mismatch",
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
        provider_refund_id: "re_currency_mismatch"
      )

      stripe_refund = Stripe::Refund.construct_from(
        id: "re_currency_mismatch",
        object: "refund",
        amount: 5000,
        currency: "usd",
        status: "failed",
        payment_intent: "pi_currency_mismatch"
      )

      expect(Stripe::Refund)
        .to receive(:retrieve)
        .with("re_currency_mismatch")
        .and_return(stripe_refund)

      expect {
        described_class.new(refund: refund).call
      }.to raise_error(
        Payments::ReconcileRefund::CurrencyMismatch
      )

      expect(refund.reload.status).to eq("processing")
      expect(refund.provider_refund_id).to eq("re_currency_mismatch")
      expect(refund.refunded_at).to be_nil
    end

    it "rejects a failed Stripe refund with a different refund ID" do
      payment = create(
        :payment,
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_refund_id_mismatch",
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
        provider_refund_id: "re_expected"
      )

      stripe_refund = Stripe::Refund.construct_from(
        id: "re_different",
        object: "refund",
        amount: 5000,
        currency: "gbp",
        status: "failed",
        payment_intent: "pi_refund_id_mismatch"
      )

      expect(Stripe::Refund)
        .to receive(:retrieve)
        .with("re_expected")
        .and_return(stripe_refund)

      expect {
        described_class.new(refund: refund).call
      }.to raise_error(
        Payments::ReconcileRefund::ProviderRefundMismatch
      )

      expect(refund.reload.status).to eq("processing")
      expect(refund.provider_refund_id).to eq("re_expected")
      expect(refund.refunded_at).to be_nil
    end
  end
end
