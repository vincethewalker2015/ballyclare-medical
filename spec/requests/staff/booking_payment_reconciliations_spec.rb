require "rails_helper"

RSpec.describe "Staff unresolved booking payment review", type: :request do
  let(:practice) { create(:practice) }
  let(:user) { create(:user) }

  let!(:membership) do
    create(:staff_member, practice: practice, user: user,
      active: true, access_level: "staff_admin")
  end

  it "lists stale unresolved booking payments without Stripe IDs only for the staff member's practice" do
    own_patient = create(:patient, practice: practice)
    other_patient = create(:patient, practice: create(:practice))
    own_payment = create(:payment, appointment: nil, patient: own_patient,
      status: "pending", provider_payment_id: nil)
    foreign_payment = create(:payment, appointment: nil, patient: other_patient,
      status: "pending", provider_payment_id: nil)
    own_payment.update_columns(updated_at: 20.minutes.ago)
    foreign_payment.update_columns(updated_at: 20.minutes.ago)

    sign_in user

    expect {
      get practice_booking_payment_reconciliations_path
    }.not_to change(Payment, :count)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_payment.id.to_s)
    expect(response.body).not_to include(foreign_payment.id.to_s)
    expect(own_payment.reload.status).to eq("pending")
    expect(own_payment.provider_payment_id).to be_nil
  end
  it "includes stale guest booking payments and excludes other practices" do
    make_guest_payment = lambda do |owner_practice|
      slot = create(:appointment_slot, practice: owner_practice)
      guest = GuestBooking.create!(
        practice: owner_practice, appointment_slot: slot,
        first_name: "Guest", last_name: "Visitor",
        date_of_birth: Date.new(1990, 1, 1),
        email: "guest@example.test", phone: "07123456789",
        consultation_reason: "Consultation",
        expires_at: 1.hour.from_now
      )
      payment = create(:payment, appointment: nil, patient: nil,
        guest_booking: guest, status: "processing",
        provider_payment_id: "pi_guest_#{guest.id}")
      payment.update_columns(updated_at: 20.minutes.ago)
      payment
    end

    own_payment = make_guest_payment.call(practice)
    foreign_payment = make_guest_payment.call(create(:practice))

    sign_in user
    get practice_booking_payment_reconciliations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_payment.provider_payment_id)
    expect(response.body).not_to include(foreign_payment.provider_payment_id)
  end

  it "excludes recent and resolved payments from the review queue" do
    patient = create(:patient, practice: practice)
    stale = create(:payment, appointment: nil, patient: patient,
      status: "pending", provider_payment_id: nil)
    recent = create(:payment, appointment: nil, patient: patient,
      status: "processing", provider_payment_id: "pi_recent_only")
    resolved = create(:payment, appointment: nil, patient: patient,
      status: "failed", provider_payment_id: "pi_resolved_only")
    stale.update_columns(updated_at: 20.minutes.ago)
    resolved.update_columns(updated_at: 20.minutes.ago)

    sign_in user
    get practice_booking_payment_reconciliations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(stale.id.to_s)
    expect(response.body).not_to include("pi_recent_only", "pi_resolved_only")
    expect(recent.reload.status).to eq("processing")
    expect(resolved.reload.status).to eq("failed")
  end

  it "rejects unauthenticated and basic staff access" do
    get practice_booking_payment_reconciliations_path
    expect(response).to redirect_to(new_user_session_path)

    membership.update!(access_level: "staff")
    sign_in user
    get practice_booking_payment_reconciliations_path

    expect(response).to have_http_status(:forbidden)
  end

  it "refuses to reconcile a Stripe intent belonging to another payment" do
    patient = create(:patient, practice: practice)
    payment = create(:payment, appointment: nil, patient: patient,
      status: "pending", provider_payment_id: nil)
    payment.update_columns(updated_at: 20.minutes.ago)

    stripe_intent = instance_double(Stripe::PaymentIntent,
      id: "pi_unrelated", status: "succeeded",
      metadata: { "payment_id" => "some-other-payment" },
      amount_received: payment.amount_cents,
      currency: payment.currency.downcase)
    allow(Stripe::PaymentIntent).to receive(:retrieve)
      .with("pi_unrelated").and_return(stripe_intent)

    sign_in user

    expect {
      post verify_practice_booking_payment_reconciliation_path(payment),
        params: { payment_intent_id: "pi_unrelated" }
    }.not_to change(Appointment, :count)

    expect(response).to redirect_to(practice_booking_payment_reconciliations_path)
    expect(payment.reload.status).to eq("pending")
    expect(payment.provider_payment_id).to be_nil
  end

end
