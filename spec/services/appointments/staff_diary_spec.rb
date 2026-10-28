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
  it "excludes fully paid bookings but includes partially paid bookings with their remaining balance" do
    practice = create(:practice)
    clinician = create(:staff_member, practice: practice, staff_type: "doctor")
    administrator = create(:staff_member, practice: practice,
      staff_type: "administrator", access_level: "staff_admin")
    patient = create(:patient, practice: practice)
    availability = create(:availability_block, practice: practice, clinician: clinician)
    starts_at = availability.starts_at + 1.hour

    fully_paid_slot = create(:appointment_slot, practice: practice, clinician: clinician,
      availability_block: availability, starts_at: starts_at, ends_at: starts_at + 20.minutes)
    partially_paid_slot = create(:appointment_slot, practice: practice, clinician: clinician,
      availability_block: availability, starts_at: starts_at + 20.minutes,
      ends_at: starts_at + 40.minutes)

    fully_paid = create(:appointment, practice: practice, clinician: clinician,
      patient: patient, appointment_slot: fully_paid_slot, status: "booked")
    partially_paid = create(:appointment, practice: practice, clinician: clinician,
      patient: patient, appointment_slot: partially_paid_slot, status: "booked")

    [fully_paid, partially_paid].each do |appointment|
      Billing::CreateCharge.new(
        appointment: appointment, description: "Appointment",
        charge_type: "appointment", amount_cents: 6_500
      ).call
    end
    create(:payment, appointment: fully_paid, patient: patient,
      amount_cents: 6_500, status: "succeeded")
    create(:payment, appointment: partially_paid, patient: patient,
      amount_cents: 2_000, status: "succeeded")

    diary = described_class.new(
      practice: practice, staff_member: administrator, view: "payment_due",
      layout: "list", clinician_id: nil, date: nil
    ).call

    expect(diary.appointments).to include(partially_paid)
    expect(diary.appointments).not_to include(fully_paid)
    expect(diary.balances.fetch(partially_paid.id)[:balance_cents]).to eq(4_500)
    expect(diary.balances.fetch(fully_paid.id)[:balance_cents]).to eq(0)
  end

end
