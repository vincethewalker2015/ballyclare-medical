require "rails_helper"

RSpec.describe "Guest payment failure page", type: :request do
  it "explains a failed payment and offers a fresh appointment search" do
    practice = create(:practice)
    clinician = create(:staff_member, practice: practice, staff_type: "doctor")
    starts_at = 3.days.from_now.change(hour: 10, min: 0)
    block = create(:availability_block, practice: practice, clinician: clinician,
      starts_at: starts_at - 1.hour, ends_at: starts_at + 1.hour, bookable_online: true)
    slot = create(:appointment_slot, practice: practice, clinician: clinician,
      availability_block: block, starts_at: starts_at, ends_at: starts_at + 20.minutes)

    post guest_booking_details_path, params: { guest_booking: {
      appointment_slot_id: slot.id, first_name: "Guest", last_name: "Visitor",
      date_of_birth: "1990-01-01", email: "guest@example.com",
      phone: "07700900123", consultation_reason: "One-off consultation"
    } }
    guest = GuestBooking.order(:created_at).last
    payment = Payment.create!(guest_booking: guest, provider: "stripe",
      amount_cents: 5000, currency: practice.currency, status: "failed",
      idempotency_key: SecureRandom.uuid)

    get guest_booking_payment_path(payment)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Payment not completed")
    expect(response.body).to include("Choose an appointment and try again")
    expect(response.body).to include("contact the practice before paying again")
    expect(response.body).to include(guest_booking_path)
    expect(guest.reload.patient).to be_nil
  end
  it "reports a completed refund rather than asking for another refund" do
    practice = create(:practice)
    clinician = create(:staff_member, practice: practice, staff_type: "doctor")
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
    payment = Payment.create!(guest_booking: guest, provider: "stripe",
      amount_cents: 4000, currency: practice.currency, status: "requires_refund",
      idempotency_key: SecureRandom.uuid)
    create(:refund, payment: payment, amount_cents: 4000,
      currency: practice.currency, status: "succeeded")

    get guest_booking_payment_path(payment)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Your refund has been completed")
    expect(response.body).to include("Your full payment has been refunded")
    expect(response.body).not_to include("Contact the practice to arrange a refund")
  end

end
