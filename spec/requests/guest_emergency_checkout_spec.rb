require "rails_helper"

RSpec.describe "Guest checkout during a declared Stripe outage", type: :request do
  let(:practice) { create(:practice) }
  let(:clinician) { create(:staff_member, practice: practice, staff_type: "doctor") }
  let(:administrator) do
    create(:staff_member, practice: practice, staff_type: "administrator",
      access_level: "senior_staff_admin")
  end

  it "shows an emergency unpaid-booking option instead of initiating Stripe when the outage is active" do
    create(:consultation_fee, practice: practice, clinician_type: "doctor")
    starts_at = 3.days.from_now.change(hour: 10, min: 0)
    block = create(:availability_block, practice: practice, clinician: clinician,
      starts_at: starts_at - 1.hour, ends_at: starts_at + 1.hour, bookable_online: true)
    slot = create(:appointment_slot, practice: practice, clinician: clinician,
      availability_block: block, starts_at: starts_at, ends_at: starts_at + 20.minutes)

    post guest_booking_details_path, params: { guest_booking: {
      appointment_slot_id: slot.id, first_name: "Guest", last_name: "Visitor",
      date_of_birth: "1990-01-01", email: "visitor@example.com",
      phone: "07700900123", consultation_reason: "Consultation"
    } }
    expect(response).to redirect_to(guest_booking_review_path)

    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: administrator, reason: "Stripe outage independently confirmed"
    )

    get guest_booking_review_path
    expect(response.body).to include("Book now — pay later")
    expect(response.body).to include("payment remains outstanding")
    expect(response.body).not_to include("Continue to secure payment")
    expect(Payment.count).to eq(0)
    expect(Appointment.count).to eq(0)
  end
end
