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
  it "confirms a guest appointment as booked but unpaid through the protected emergency POST" do
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

    expect(Stripe::PaymentIntent).not_to receive(:create)
    expect {
      post "/book/emergency-unpaid"
    }.to change(Appointment, :count).by(1)
      .and change(Payment, :count).by(0)

    appointment = Appointment.order(:id).last
    expect(appointment.status).to eq("booked")
    expect(appointment.appointment_charges.sole.status).to eq("active")
    expect(appointment.appointment_charges.sole.amount_cents).to eq(6_500)

    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Booked — Unpaid")
    expect(response.body).to include("payment remains outstanding")
  end

  it "rejects the emergency POST if the outage was deactivated after the review page was shown" do
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

    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: administrator, reason: "Stripe outage confirmed"
    )
    get guest_booking_review_path
    expect(response.body).to include("Book now — pay later")

    Payments::StripeOutageDeclaration.deactivate!(
      practice: practice, actor: administrator, reason: "Stripe service restored"
    )

    expect(Stripe::PaymentIntent).not_to receive(:create)
    expect {
      post guest_booking_emergency_unpaid_path
    }.not_to change(Appointment, :count)
    expect(Payment.count).to eq(0)
    expect(response).to redirect_to(guest_booking_review_path)

    follow_redirect!
    expect(response.body).not_to include("Book now — pay later")
    expect(response.body).to include("Continue to secure payment")
  end

  it "never converts an ambiguous pending Stripe payment into an unpaid emergency booking" do
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
    guest = GuestBooking.order(:id).last
    hold = GuestBookings::ReserveSlot.new(guest_booking: guest).call
    payment = Payment.create!(
      appointment_hold: hold, guest_booking: guest, provider: "stripe",
      currency: "GBP", amount_cents: 6_500, status: "pending",
      idempotency_key: SecureRandom.uuid
    )

    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: administrator, reason: "Stripe outage confirmed"
    )

    get guest_booking_review_path
    expect(response.body).not_to include("Book now — pay later")

    expect(Stripe::PaymentIntent).not_to receive(:create)
    expect {
      post guest_booking_emergency_unpaid_path
    }.not_to change(Appointment, :count)

    expect(response).to redirect_to(guest_booking_review_path)
    expect(Payment.where(guest_booking: guest).pluck(:id)).to eq([payment.id])
    expect(payment.reload.status).to eq("pending")
    expect(guest.reload.status).to eq("payment_pending")
  end

  %w[processing succeeded failed cancelled requires_refund].each do |payment_status|
    it "rejects emergency unpaid booking when an existing Stripe payment is #{payment_status}" do
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
      guest = GuestBooking.order(:id).last
      hold = GuestBookings::ReserveSlot.new(guest_booking: guest).call
      payment = Payment.create!(
        appointment_hold: hold, guest_booking: guest, provider: "stripe",
        currency: "GBP", amount_cents: 6_500, status: payment_status,
        idempotency_key: SecureRandom.uuid
      )

      Payments::StripeOutageDeclaration.activate!(
        practice: practice, actor: administrator, reason: "Stripe outage confirmed"
      )

      get guest_booking_review_path
      expect(response.body).not_to include("Book now — pay later")

      expect(Stripe::PaymentIntent).not_to receive(:create)
      expect {
        post guest_booking_emergency_unpaid_path
      }.not_to change(Appointment, :count)

      expect(response).to redirect_to(guest_booking_review_path)
      expect(Payment.where(guest_booking: guest).pluck(:id)).to eq([payment.id])
      expect(payment.reload.status).to eq(payment_status)
    end
  end

end
