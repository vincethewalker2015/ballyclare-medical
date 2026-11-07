require "rails_helper"

RSpec.describe "Stripe outage failure monitoring" do
  let(:payment) { create(:payment, status: "pending") }

  it "records a Stripe connection error during PaymentIntent creation and re-raises it" do
    allow(Stripe::PaymentIntent).to receive(:create)
      .and_raise(Stripe::APIConnectionError.new("Stripe unavailable"))

    expect {
      PaymentProviders::StripeProvider::CreatePayment.new(payment: payment).call
    }.to raise_error(Stripe::APIConnectionError)

    event = AuditEvent.where(action: Payments::StripeOutageMonitor::FAILURE_ACTION).sole
    expect(event.practice).to eq(payment.appointment.practice)
    expect(event.metadata.fetch("source")).to eq("payment_intent_create")
    expect(payment.reload.status).to eq("pending")
    expect(Payments::StripeOutageDeclaration.active?(practice: payment.appointment.practice)).to be(false)
  end

  it "records a Stripe API failure during reconciliation without changing payment status" do
    payment.update!(status: "processing", provider_payment_id: "pi_monitoring")
    payment.update_columns(updated_at: 20.seconds.ago)
    allow(Stripe::PaymentIntent).to receive(:retrieve)
      .with("pi_monitoring").and_raise(Stripe::APIConnectionError.new("Stripe unavailable"))

    expect {
      Payments::ReconcileStripeStatus.new(payment: payment).call
    }.to raise_error(Stripe::APIConnectionError)

    event = AuditEvent.where(action: Payments::StripeOutageMonitor::FAILURE_ACTION).sole
    expect(event.practice).to eq(payment.appointment.practice)
    expect(event.metadata.fetch("source")).to eq("payment_intent_retrieve")
    expect(payment.reload.status).to eq("processing")
  end

  it "does not confuse a card decline with a Stripe outage" do
    allow(Stripe::PaymentIntent).to receive(:create)
      .and_raise(Stripe::CardError.new("Your card was declined", "card"))

    expect {
      PaymentProviders::StripeProvider::CreatePayment.new(payment: payment).call
    }.to raise_error(Stripe::CardError)

    expect(AuditEvent.where(action: Payments::StripeOutageMonitor::FAILURE_ACTION)).to be_empty
  end
end
