require "rails_helper"

RSpec.describe Appointments::StaffDiary do
  it "includes booked unpaid appointments in Payment due while excluding cancelled appointments" do
    practice = create(:practice)
    clinician = create(:staff_member, practice: practice, staff_type: "doctor")
    administrator = create(:staff_member, practice: practice,
      staff_type: "administrator", access_level: "staff_admin")
    patient = create(:patient, practice: practice)
    slot = create(:appointment_slot, practice: practice, clinician: clinician)
    appointment = create(:appointment, practice: practice, clinician: clinician,
      patient: patient, appointment_slot: slot, status: "booked")
    Billing::CreateCharge.new(
      appointment: appointment, description: "Appointment",
      charge_type: "appointment", amount_cents: 6_500
    ).call

    cancelled_start = 2.days.from_now.change(hour: 10, min: 0)
    cancelled_block = create(:availability_block, practice: practice, clinician: clinician,
      starts_at: cancelled_start - 1.hour, ends_at: cancelled_start + 1.hour)
    cancelled_slot = create(:appointment_slot, practice: practice, clinician: clinician,
      availability_block: cancelled_block, starts_at: cancelled_start,
      ends_at: cancelled_start + 20.minutes)
    cancelled = create(:appointment, practice: practice, clinician: clinician,
      patient: patient, appointment_slot: cancelled_slot, status: "booked")
    Billing::CreateCharge.new(
      appointment: cancelled, description: "Appointment",
      charge_type: "appointment", amount_cents: 6_500
    ).call
    cancelled.update!(status: "cancelled")

    diary = described_class.new(
      practice: practice, staff_member: administrator, view: "payment_due",
      layout: "list", clinician_id: nil, date: nil
    ).call

    expect(diary.appointments).to include(appointment)
    expect(diary.appointments).not_to include(cancelled)
    expect(diary.balances.fetch(appointment.id)[:balance_cents]).to eq(6_500)
  end
end
