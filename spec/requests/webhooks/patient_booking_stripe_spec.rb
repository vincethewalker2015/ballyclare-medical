require "rails_helper"

RSpec.describe "Patient booking Stripe webhook", type: :request do
  let(:slot) { create(:appointment_slot) }
  let(:patient) { create(:patient, practice: slot.practice) }
  let(:hold) { slot.hold_for!(patient: patient) }
  let(:payment) do
    Payment.create!(appointment_hold: hold, patient: patient,
      provider: "stripe", provider_payment_id: "pi_patient_webhook",
      amount_cents: 6500, currency: slot.practice.currency,
      status: "processing", idempotency_key: SecureRandom.uuid)
  end
  let(:intent) do
    instance_double(Stripe::PaymentIntent, id: "pi_patient_webhook",
      amount_received: 6500, currency: slot.practice.currency.downcase)
  end

  before do
    payment
    event = instance_double(Stripe::Event, type: "payment_intent.succeeded",
      data: double(object: intent))
    allow(Stripe::Webhook).to receive(:construct_event).and_return(event)
  end

  def deliver_event
    post "/webhooks/stripe", params: "{}", headers: {
      "Stripe-Signature" => "test-signature", "CONTENT_TYPE" => "application/json"
    }
    expect(response).to have_http_status(:ok)
  end

  it "books exactly once and records the matching consultation charge" do
    expect { deliver_event }.to change(Appointment, :count).by(1)
      .and change(AppointmentCharge, :count).by(1)

    appointment = payment.reload.appointment
    expect(payment.status).to eq("succeeded")
    expect(appointment.patient).to eq(patient)
    expect(appointment.appointment_charges.first.amount_cents).to eq(6500)
    expect(Billing::AppointmentBalance.new(appointment: appointment).call[:balance_cents]).to eq(0)

    expect { deliver_event }.not_to change(Appointment, :count)
    expect(appointment.appointment_charges.count).to eq(1)
  end

  it "records a refund requirement rather than booking after the hold expires" do
    hold.update!(expires_at: 1.minute.ago)
    expect { deliver_event }.not_to change(Appointment, :count)
    expect(payment.reload.status).to eq("requires_refund")
    expect { deliver_event }.not_to change(Appointment, :count)
    expect(payment.reload.status).to eq("requires_refund")
  end
end
