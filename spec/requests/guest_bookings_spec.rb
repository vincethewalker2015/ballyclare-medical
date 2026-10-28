require "rails_helper"

RSpec.describe "Guest booking entry", type: :request do
  it "allows visitors to open the guest booking page without signing in" do
    get guest_booking_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Book as a guest")
    expect(response.body).to include("account or password")
    expect(response.body).to include("guest checkout")
  end

  it "shows online clinician slots without requiring a patient account" do
    practice = create(:practice)
    clinician = create(:staff_member, practice: practice, staff_type: "doctor")
    starts_at = 3.days.from_now.change(hour: 10, min: 0)
    block = create(:availability_block, practice: practice, clinician: clinician,
      starts_at: starts_at - 1.hour, ends_at: starts_at + 1.hour, bookable_online: true)
    create(:appointment_slot, practice: practice, clinician: clinician,
      availability_block: block, starts_at: starts_at, ends_at: starts_at + 20.minutes)

    get guest_booking_path, params: { practice_id: practice.id, clinician_id: clinician.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(clinician.full_name)
    expect(response.body).to include(starts_at.in_time_zone(practice.timezone).strftime("%A, %d %B"))
    expect(AppointmentHold.count).to eq(0)
  end

  it "does not expose clinicians from another practice" do
    practice = create(:practice)
    other_practice = create(:practice)
    clinician = create(:staff_member, practice: other_practice, staff_type: "doctor")
    starts_at = 3.days.from_now.change(hour: 10, min: 0)
    create(:availability_block, practice: practice,
      clinician: create(:staff_member, practice: practice, staff_type: "doctor"),
      starts_at: starts_at - 1.hour, ends_at: starts_at + 1.hour, bookable_online: true)

    get guest_booking_path, params: { practice_id: practice.id, clinician_id: clinician.id }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.css("select[name=clinician_id] option").map { |option| option["value"] }).not_to include(clinician.id.to_s)
    expect(response.parsed_body.css("h3").map { |heading| heading.text.squish }).not_to include("Available appointments")
  end

  it "collects guest details without creating a patient or taking payment" do
    practice = create(:practice)
    clinician = create(:staff_member, practice: practice, staff_type: "doctor")
    starts_at = 3.days.from_now.change(hour: 10, min: 0)
    block = create(:availability_block, practice: practice, clinician: clinician,
      starts_at: starts_at - 1.hour, ends_at: starts_at + 1.hour, bookable_online: true)
    slot = create(:appointment_slot, practice: practice, clinician: clinician,
      availability_block: block, starts_at: starts_at, ends_at: starts_at + 20.minutes)

    get new_guest_booking_path, params: { appointment_slot_id: slot.id }
    expect(response).to have_http_status(:ok)

    expect {
      post guest_booking_details_path, params: { guest_booking: {
        appointment_slot_id: slot.id, first_name: "Guest", last_name: "Visitor",
        date_of_birth: "1990-01-01", email: "guest@example.com",
        phone: "07700900123", consultation_reason: "One-off consultation"
      } }
    }.to change(GuestBooking, :count).by(1)
      .and change(Patient, :count).by(0)
      .and change(Payment, :count).by(0)

    expect(response).to redirect_to(guest_booking_review_path)
    get guest_booking_review_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No clinical Patient record is created before payment")
  end

  it "does not list practices without online availability" do
    practice = create(:practice, name: "No online appointments")
    create(:staff_member, practice: practice)

    get guest_booking_path

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.css("ul li").map { |item| item.text.squish }).not_to include(practice.name)
  end
  it "preserves an unresolved Stripe PaymentIntent without reopening guest checkout" do
    practice = create(:practice)
    clinician = create(:staff_member, practice: practice, staff_type: "doctor")
    create(:consultation_fee, practice: practice, clinician_type: "doctor")
    starts_at = 3.days.from_now.change(hour: 10, min: 0)
    block = create(:availability_block, practice: practice, clinician: clinician,
      starts_at: starts_at - 1.hour, ends_at: starts_at + 1.hour, bookable_online: true)
    slot = create(:appointment_slot, practice: practice, clinician: clinician,
      availability_block: block, starts_at: starts_at, ends_at: starts_at + 20.minutes)

    post guest_booking_details_path, params: { guest_booking: {
      appointment_slot_id: slot.id, first_name: "Guest", last_name: "Visitor",
      date_of_birth: "1990-01-01", email: "guest@example.com",
      phone: "07700900123", consultation_reason: "Consultation"
    } }
    guest = GuestBooking.order(:created_at).last
    hold = GuestBookings::ReserveSlot.new(guest_booking: guest).call
    payment = Payment.create!(
      appointment_hold: hold, guest_booking: guest, provider: "stripe",
      currency: practice.currency, amount_cents: 6_500, status: "processing",
      provider_payment_id: "pi_existing_guest", idempotency_key: SecureRandom.uuid
    )
    original_key = payment.idempotency_key

    expect(Stripe::PaymentIntent).not_to receive(:create)
    expect(Stripe::PaymentIntent).not_to receive(:retrieve)

    expect { post guest_booking_checkout_path }.not_to change(Payment, :count)
    expect(response).to redirect_to(guest_booking_review_path)
    expect(payment.reload.provider_payment_id).to eq("pi_existing_guest")
    expect(payment.idempotency_key).to eq(original_key)
    expect(payment.status).to eq("processing")
    expect(Appointment.count).to eq(0)

    get guest_booking_review_path
    expect(response.body).to include("Payment verification pending")
    expect(response.body).not_to include("Continue to secure payment")
    expect(response.body).not_to include("Book now — pay later")
  end

end
