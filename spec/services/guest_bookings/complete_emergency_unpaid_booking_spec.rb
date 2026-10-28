require "rails_helper"

RSpec.describe GuestBookings::CompleteEmergencyUnpaidBooking do
  let(:practice) { create(:practice) }
  let(:clinician) { create(:staff_member, practice: practice, staff_type: "doctor") }
  let(:administrator) do
    create(:staff_member, practice: practice, staff_type: "administrator",
      access_level: "senior_staff_admin")
  end
  let(:starts_at) { 3.days.from_now.change(hour: 10, min: 0) }
  let(:availability_block) do
    create(:availability_block, practice: practice, clinician: clinician,
      starts_at: starts_at - 1.hour, ends_at: starts_at + 1.hour, bookable_online: true)
  end
  let(:slot) do
    create(:appointment_slot, practice: practice, clinician: clinician,
      availability_block: availability_block, starts_at: starts_at,
      ends_at: starts_at + 20.minutes)
  end
  let(:guest) do
    GuestBooking.create!(
      practice: practice, appointment_slot: slot,
      first_name: "Guest", last_name: "Visitor",
      date_of_birth: Date.new(1990, 1, 1),
      email: "visitor@example.com", phone: "07700900123",
      consultation_reason: "Consultation", status: "draft",
      expires_at: 30.minutes.from_now
    )
  end

  it "books an outstanding-charge appointment without contacting Stripe during a declared outage" do
    create(:consultation_fee, practice: practice, clinician_type: "doctor")
    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: administrator, reason: "Stripe outage independently confirmed"
    )
    hold = GuestBookings::ReserveSlot.new(guest_booking: guest).call

    expect(Stripe::PaymentIntent).not_to receive(:create)
    expect {
      @appointment = described_class.new(hold: hold).call
    }.to change(Appointment, :count).by(1)
      .and change(Patient, :count).by(1)
      .and change(Payment, :count).by(0)

    expect(@appointment.status).to eq("booked")
    expect(@appointment.patient.patient_type).to eq("external")
    expect(@appointment.appointment_charges.sole.amount_cents).to eq(6_500)
    expect(@appointment.appointment_charges.sole.status).to eq("active")
    expect(guest.reload.status).to eq("completed")
    expect(AppointmentHold.exists?(hold.id)).to be(false)
  end
  it "rejects a repeated completion without creating another appointment, patient or charge" do
    create(:consultation_fee, practice: practice, clinician_type: "doctor")
    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: administrator, reason: "Stripe outage independently confirmed"
    )
    hold = GuestBookings::ReserveSlot.new(guest_booking: guest).call
    appointment = described_class.new(hold: hold).call

    expect {
      expect { described_class.new(hold: hold).call }
        .to raise_error(described_class::Unavailable)
    }.not_to change {
      [Appointment.count, Patient.count, AppointmentCharge.count]
    }

    expect(Appointment.where(appointment_slot: slot).sole.id).to eq(appointment.id)
  end

  %w[pending processing succeeded failed cancelled requires_refund].each do |status|
    it "rejects emergency booking when a #{status} Stripe payment already exists" do
      create(:consultation_fee, practice: practice, clinician_type: "doctor")
      Payments::StripeOutageDeclaration.activate!(
        practice: practice, actor: administrator, reason: "Stripe outage independently confirmed"
      )
      hold = GuestBookings::ReserveSlot.new(guest_booking: guest).call
      Payment.create!(
        appointment_hold: hold,
        guest_booking: guest,
        provider: "stripe",
        currency: "GBP",
        amount_cents: 6_500,
        status: status,
        idempotency_key: SecureRandom.uuid
      )

      expect {
        expect { described_class.new(hold: hold).call }
          .to raise_error(described_class::Unavailable, /not permitted/)
      }.not_to change {
        [Appointment.count, Patient.count, AppointmentCharge.count]
      }

      expect(guest.reload.status).to eq("payment_pending")
      expect(AppointmentHold.exists?(hold.id)).to be(true)
    end
  end

end
