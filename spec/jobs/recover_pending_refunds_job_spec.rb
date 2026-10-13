require "rails_helper"

RSpec.describe RecoverPendingRefundsJob do
  describe "#perform" do
    it "enqueues processing for a pending refund" do
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

      expect(ProcessRefundJob)
        .to receive(:perform_later)
        .with(refund.id)

      described_class.new.perform
    end

    it "does not enqueue refunds that are already processing or completed" do
      payment = create(
        :payment,
        status: "succeeded",
        amount_cents: 5000,
        currency: "GBP",
        paid_at: Time.current
      )

      %w[processing succeeded failed cancelled].each do |status|
        create(
          :refund,
          payment: payment,
          amount_cents: 1000,
          currency: "GBP",
          status: status
        )
      end

      expect(ProcessRefundJob).not_to receive(:perform_later)

      described_class.new.perform
    end

    it "continues recovering other refunds when one enqueue fails" do
      payment = create(
        :payment,
        status: "succeeded",
        amount_cents: 5000,
        currency: "GBP",
        paid_at: Time.current
      )

      refunds = 2.times.map do
        create(
          :refund,
          payment: payment,
          amount_cents: 1000,
          currency: "GBP",
          status: "pending"
        )
      end

      attempted_ids = []

      allow(ProcessRefundJob).to receive(:perform_later) do |refund_id|
        attempted_ids << refund_id

        raise StandardError, "Queue temporarily unavailable" if attempted_ids.size == 1
      end

      expect {
        described_class.new.perform
      }.not_to raise_error

      expect(attempted_ids).to match_array(refunds.map(&:id))
    end

    it "reuses the existing refund when recovery runs repeatedly" do
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

      expect(ProcessRefundJob)
        .to receive(:perform_later)
        .with(refund.id)
        .twice

      expect {
        2.times { described_class.new.perform }
      }.not_to change(Refund, :count)

      expect(refund.reload.status).to eq("pending")
    end
  end
end
