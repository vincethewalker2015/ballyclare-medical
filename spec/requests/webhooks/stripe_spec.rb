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
    def signed_stripe_request(payload, secret: webhook_secret, timestamp: Time.now.to_i)
      signed_content = "#{timestamp}.#{payload}"
      signature = OpenSSL::HMAC.hexdigest("SHA256", secret, signed_content)
      post "/webhooks/stripe", params: payload,
        headers: {
          "Stripe-Signature" => "t=#{timestamp},v1=#{signature}",
          "CONTENT_TYPE" => "application/json"
        }
    end

    it "verifies a genuinely signed Stripe payload without mocking verification" do
      payload = { id: "evt_signed_test", object: "event",
        type: "payment_intent.created", data: { object: { id: "pi_signed_test", object: "payment_intent" } } }.to_json

      expect(Payments::HandleSucceeded).not_to receive(:new)
      signed_stripe_request(payload)

      expect(response).to have_http_status(:ok)
    end

    it "rejects a tampered payload even when the signature was valid for the original body" do
      original = { id: "evt_original", object: "event",
        type: "payment_intent.created", data: { object: { id: "pi_original", object: "payment_intent" } } }.to_json
      tampered = original.sub("evt_original", "evt_modified")
      timestamp = Time.now.to_i
      signature = OpenSSL::HMAC.hexdigest("SHA256", webhook_secret, "#{timestamp}.#{original}")

      expect(Payments::HandleSucceeded).not_to receive(:new)
      post "/webhooks/stripe", params: tampered,
        headers: {
          "Stripe-Signature" => "t=#{timestamp},v1=#{signature}",
          "CONTENT_TYPE" => "application/json"
        }

      expect(response).to have_http_status(:bad_request)
    end

    it "rejects a correctly signed but stale Stripe timestamp" do
      payload = { id: "evt_stale", object: "event",
        type: "payment_intent.created", data: { object: { id: "pi_stale", object: "payment_intent" } } }.to_json

      signed_stripe_request(payload, timestamp: 1.hour.ago.to_i)

      expect(response).to have_http_status(:bad_request)
    end

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

    it "completes a paid patient hold only once when Stripe delivers the success event twice" do
      slot = create(:appointment_slot)
      patient = create(:patient, practice: slot.practice)
      hold = slot.hold_for!(patient: patient)
      payment = Payment.create!(
        appointment_hold: hold,
        patient: patient,
        provider: "stripe",
        provider_payment_id: "pi_webhook_duplicate",
        amount_cents: 5000,
        currency: slot.practice.currency,
        status: "processing",
        idempotency_key: SecureRandom.uuid
      )
      payment_intent = instance_double(
        Stripe::PaymentIntent,
        id: "pi_webhook_duplicate",
        amount_received: 5000,
        currency: slot.practice.currency.downcase
      )
      event = instance_double(
        Stripe::Event,
        type: "payment_intent.succeeded",
        data: double(object: payment_intent)
      )
      allow(Stripe::Webhook).to receive(:construct_event).and_return(event)

      deliver_event = lambda do
        post "/webhooks/stripe",
          params: "{}",
          headers: {
            "Stripe-Signature" => "valid-signature",
            "CONTENT_TYPE" => "application/json"
          }
        expect(response).to have_http_status(:ok)
      end

      expect {
        deliver_event.call
        deliver_event.call
      }.to change(Appointment, :count).by(1)
        .and change(AppointmentCharge, :count).by(1)

      expect(payment.reload.status).to eq("succeeded")
      expect(payment.appointment).to be_present
      expect(payment.appointment.appointment_slot).to eq(slot)
      expect(payment.appointment.appointment_charges.first.amount_cents).to eq(5000)
    end

    it "processes duplicate refund.updated events only once" do
      payment = create(:payment, status: "succeeded", amount_cents: 5000,
        currency: "GBP", paid_at: Time.current)
      refund = create(:refund, payment: payment, amount_cents: 2000,
        currency: "GBP", status: "processing", provider_refund_id: "re_webhook_duplicate")
      stripe_refund = Stripe::Refund.construct_from(
        id: "re_webhook_duplicate", object: "refund", amount: 2000,
        currency: "gbp", status: "succeeded"
      )
      event = instance_double(Stripe::Event, type: "refund.updated",
        data: double(object: stripe_refund))
      allow(Stripe::Webhook).to receive(:construct_event).and_return(event)

      deliver = lambda do
        post "/webhooks/stripe", params: "{}",
          headers: { "Stripe-Signature" => "test-signature",
            "CONTENT_TYPE" => "application/json" }
        expect(response).to have_http_status(:ok)
      end

      deliver.call
      first_refunded_at = refund.reload.refunded_at
      expect(refund.status).to eq("succeeded")
      expect(first_refunded_at).to be_present

      expect { deliver.call }.not_to change { refund.reload.attributes }
      expect(refund.refunded_at).to eq(first_refunded_at)
    end

    it "does not mutate a failed payment when payment_intent.payment_failed is redelivered" do
      payment = create(:payment, provider: "stripe", status: "processing",
        provider_payment_id: "pi_failed_duplicate", amount_cents: 5000,
        currency: "GBP")
      intent = instance_double(Stripe::PaymentIntent,
        id: "pi_failed_duplicate", amount: 5000, currency: "gbp")
      event = instance_double(Stripe::Event, type: "payment_intent.payment_failed",
        data: double(object: intent))
      allow(Stripe::Webhook).to receive(:construct_event).and_return(event)

      deliver = lambda do
        post "/webhooks/stripe", params: "{}",
          headers: { "Stripe-Signature" => "test-signature",
            "CONTENT_TYPE" => "application/json" }
        expect(response).to have_http_status(:ok)
      end

      deliver.call
      expect(payment.reload.status).to eq("failed")
      failed_attributes = payment.attributes

      expect { deliver.call }.not_to change { payment.reload.attributes }
      expect(payment.attributes).to eq(failed_attributes)
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
    it "acknowledges a valid event for an unknown payment" do
      payment_intent = double(
        id: "pi_unknown"
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

      allow(Payments::HandleSucceeded)
        .to receive(:new)
        .with(payment_intent: payment_intent)
        .and_return(handler)

      allow(handler)
        .to receive(:call)
        .and_raise(
          Payments::HandleSucceeded::PaymentNotFound,
          "Payment not found for Stripe PaymentIntent pi_unknown"
        )

      expect(Rails.logger)
        .to receive(:warn)
        .with(
          "Ignoring Stripe payment_intent.succeeded: " \
          "Payment not found for Stripe PaymentIntent pi_unknown"
        )

      post "/webhooks/stripe",
          params: "{}",
          headers: {
            "Stripe-Signature" => "valid-signature",
            "CONTENT_TYPE" => "application/json"
          }

      expect(response).to have_http_status(:ok)
    end
    it "handles a failed payment intent" do
      payment_intent = double(
        id: "pi_failed_123"
      )

      event = instance_double(
        Stripe::Event,
        type: "payment_intent.payment_failed",
        data: double(object: payment_intent)
      )

      allow(Stripe::Webhook)
        .to receive(:construct_event)
        .and_return(event)

      handler = instance_double(Payments::HandleFailed)

      expect(Payments::HandleFailed)
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
    it "acknowledges a failed event for an unknown payment" do
      payment_intent = double(
        id: "pi_unknown"
      )

      event = instance_double(
        Stripe::Event,
        type: "payment_intent.payment_failed",
        data: double(object: payment_intent)
      )

      allow(Stripe::Webhook)
        .to receive(:construct_event)
        .and_return(event)

      handler = instance_double(Payments::HandleFailed)

      allow(Payments::HandleFailed)
        .to receive(:new)
        .with(payment_intent: payment_intent)
        .and_return(handler)

      allow(handler)
        .to receive(:call)
        .and_raise(
          Payments::HandleFailed::PaymentNotFound,
          "Payment not found for Stripe PaymentIntent pi_unknown"
        )

      expect(Rails.logger)
        .to receive(:warn)
        .with(
          "Ignoring Stripe payment_intent.payment_failed: " \
          "Payment not found for Stripe PaymentIntent pi_unknown"
        )

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
