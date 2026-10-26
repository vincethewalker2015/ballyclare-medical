require "rails_helper"

RSpec.describe Payments::ReconcileStripeStatus do
  let(:payment) { create(:payment, status: "processing", provider_payment_id: "pi_status_test", updated_at: 10.seconds.ago) }

  it "uses the existing success handler for successful Stripe payments" do
    intent = instance_double(Stripe::PaymentIntent, status: "succeeded")
    allow(Stripe::PaymentIntent).to receive(:retrieve).with("pi_status_test").and_return(intent)
    expect(Payments::HandleSucceeded).to receive(:new).with(payment_intent: intent).and_return(double(call: nil))
    described_class.new(payment: payment).call
  end

  it "uses staff cancellation reconciliation for appointment payments" do
    intent = instance_double(Stripe::PaymentIntent, status: "canceled")
    allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(intent)
    expect(Payments::ReconcileAppointmentPayment).to receive(:new).with(payment: payment).and_return(double(call: nil))
    described_class.new(payment: payment).call
  end

  it "does not contact Stripe for payments that are not processing" do
    payment.update!(status: "succeeded")
    expect(Stripe::PaymentIntent).not_to receive(:retrieve)
    described_class.new(payment: payment).call
  end

  it "does not reconcile recently updated payments" do
    payment.update!(updated_at: Time.current)
    expect(Stripe::PaymentIntent).not_to receive(:retrieve)
    described_class.new(payment: payment).call
  end
end
