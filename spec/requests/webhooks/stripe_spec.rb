require "rails_helper"

RSpec.describe "Stripe webhooks", type: :request do
  let(:webhook_secret) { "whsec_test_secret" }

  before do
    allow(ENV)
      .to receive(:[])
      .and_call_original

    allow(ENV)
      .to receive(:[])
      .with("STRIPE_WEBHOOK_SECRET")
      .and_return(webhook_secret)
  end

  describe "POST /webhooks/stripe" do
    it "accepts a valid Stripe event" do
      payment_intent = double(
        id: "pi_test_123"
      )

      event = instance_double(
        Stripe::Event,
        type: "payment_intent.succeeded",
        data: double(object: payment_intent)
      )

      allow(Stripe::Webhook)
        .to receive(:construct_event)
        .and_return(event)

      handler = instance_double(Payments::HandleSucceeded)

      expect(Payments::HandleSucceeded)
        .to receive(:new)
        .with(payment_intent: payment_intent)
        .and_return(handler)

      expect(handler)
        .to receive(:call)

      post "/webhooks/stripe",
           params: "{}",
           headers: {
             "Stripe-Signature" => "valid-signature",
             "CONTENT_TYPE" => "application/json"
           }

      expect(response).to have_http_status(:ok)
    end

    it "rejects an invalid Stripe signature" do
      allow(Stripe::Webhook)
        .to receive(:construct_event)
        .and_raise(
          Stripe::SignatureVerificationError.new(
            "Invalid signature",
            "invalid-signature"
          )
        )

      post "/webhooks/stripe",
           params: "{}",
           headers: {
             "Stripe-Signature" => "invalid-signature",
             "CONTENT_TYPE" => "application/json"
           }

      expect(response).to have_http_status(:bad_request)
    end

    it "accepts an unhandled but valid Stripe event" do
      event = instance_double(
        Stripe::Event,
        type: "payment_intent.created"
      )

      allow(Stripe::Webhook)
        .to receive(:construct_event)
        .and_return(event)

      expect(Payments::HandleSucceeded)
        .not_to receive(:new)

      post "/webhooks/stripe",
           params: "{}",
           headers: {
             "Stripe-Signature" => "valid-signature",
             "CONTENT_TYPE" => "application/json"
           }

      expect(response).to have_http_status(:ok)
    end
  end
end
