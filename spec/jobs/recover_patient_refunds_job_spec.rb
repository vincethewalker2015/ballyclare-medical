require "rails_helper"

RSpec.describe RecoverPatientRefundsJob, type: :job do
  let(:practice) { create(:practice) }
  let(:patient) { create(:patient, practice: practice) }
  let!(:payment) do
    create(:payment,
      appointment: nil,
      patient: patient,
      provider: "stripe",
      provider_payment_id: "pi_patient_expired_hold",
      amount_cents: 4000,
      currency: practice.currency,
      status: "requires_refund")
  end

  it "creates only one refund across repeated recovery runs" do
    allow(ProcessRefundJob).to receive(:perform_later)

    expect {
      2.times { described_class.perform_now }
    }.to change(Refund, :count).by(1)

    refund = payment.refunds.sole
    expect(refund.status).to eq("pending")
    expect(refund.amount_cents).to eq(4000)
    expect(ProcessRefundJob).to have_received(:perform_later).with(refund.id).twice
    expect(payment.reload.appointment_id).to be_nil
  end

  it "refunds only the remaining amount" do
    create(:refund, payment: payment, amount_cents: 1000,
      currency: practice.currency, status: "succeeded")
    allow(ProcessRefundJob).to receive(:perform_later)

    described_class.perform_now

    expect(payment.refunds.where(status: "pending").sole.amount_cents).to eq(3000)
  end

  it "does not issue a new refund after a failed refund" do
    create(:refund, payment: payment, amount_cents: 4000,
      currency: practice.currency, status: "failed",
      provider_refund_id: "re_patient_failed")

    expect(ProcessRefundJob).not_to receive(:perform_later)
    expect { described_class.perform_now }.not_to change(Refund, :count)
  end

  it "does not refund a successfully booked appointment" do
    payment.update!(appointment: create(:appointment, practice: practice, patient: patient))
    allow(ProcessRefundJob).to receive(:perform_later)

    expect { described_class.perform_now }.not_to change(Refund, :count)
  end
end
