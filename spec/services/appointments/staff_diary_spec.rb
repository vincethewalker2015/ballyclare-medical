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

    cancelled_slot = create(:appointment_slot, practice: practice, clinician: clinician)
    cancelled = create(:appointment, practice: practice, clinician: clinician,
      patient: patient, appointment_slot: cancelled_slot, status: "cancelled")
    Billing::CreateCharge.new(
      appointment: cancelled, description: "Appointment",
      charge_type: "appointment", amount_cents: 6_500
    ).call

    diary = described_class.new(
      practice: practice, staff_member: administrator, view: "payment_due",
      layout: "list", clinician_id: nil, date: nil
    ).call

    expect(diary.appointments).to include(appointment)
    expect(diary.appointments).not_to include(cancelled)
    expect(diary.balances.fetch(appointment.id)[:balance_cents]).to eq(6_500)
  end
end
