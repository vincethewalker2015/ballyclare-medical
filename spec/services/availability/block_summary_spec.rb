require "rails_helper"

RSpec.describe Availability::BlockSummary do
  let(:practice) do
    Practice.create!(
      name: "Test Medical Centre",
      timezone: "Europe/London",
      currency: "GBP",
      country_code: "GB"
    )
  end

  let(:clinician_user) do
    User.create!(
      email: "summary-doctor@example.com",
      password: "password123"
    )
  end

  let(:clinician) do
    StaffMember.create!(
      practice: practice,
      user: clinician_user,
      staff_type: "doctor",
      default_appointment_duration: 30
    )
  end

  let(:availability_block) do
    AvailabilityBlock.create!(
      practice: practice,
      clinician: clinician,
      starts_at: 1.day.from_now.change(hour: 9),
      ends_at: 1.day.from_now.change(hour: 11),
      slot_duration_minutes: 30,
      bookable_online: true
    )
  end

  before do
    Availability::GenerateSlots.new(
      availability_block
    ).call
  end

  subject(:summary) do
    described_class.new(
      availability_block: availability_block
    )
  end

  it "reports all generated slots as available initially" do
    expect(summary.total_slots).to eq(4)
    expect(summary.available_slots).to eq(4)
    expect(summary.booked_slots).to eq(0)
    expect(summary.held_slots).to eq(0)
  end

  it "counts a booked slot as booked rather than available" do
    slot = availability_block.appointment_slots.first

    patient = Patient.create!(
      practice: practice,
      patient_number: "SUMMARY-001",
      first_name: "Test",
      last_name: "Patient",
      date_of_birth: Date.new(1990, 1, 1)
    )

    Appointment.create!(
      practice: practice,
      appointment_slot: slot,
      patient: patient,
      clinician: clinician,
      status: "booked",
      booked_at: Time.current
    )

    expect(summary.total_slots).to eq(4)
    expect(summary.booked_slots).to eq(1)
    expect(summary.held_slots).to eq(0)
    expect(summary.available_slots).to eq(3)
  end

  it "counts a slot with an active hold as held rather than available" do
    slot = availability_block.appointment_slots.first

    patient = Patient.create!(
      practice: practice,
      patient_number: "SUMMARY-002",
      first_name: "Held",
      last_name: "Patient",
      date_of_birth: Date.new(1990, 1, 1)
    )

    slot.appointment_holds.create!(
      patient: patient,
      expires_at: 5.minutes.from_now
    )

    expect(summary.total_slots).to eq(4)
    expect(summary.booked_slots).to eq(0)
    expect(summary.held_slots).to eq(1)
    expect(summary.available_slots).to eq(3)
  end

  it "counts a slot with only an expired hold as available" do
    slot = availability_block.appointment_slots.first

    patient = Patient.create!(
      practice: practice,
      patient_number: "SUMMARY-003",
      first_name: "Expired",
      last_name: "Patient",
      date_of_birth: Date.new(1990, 1, 1)
    )

    slot.appointment_holds.create!(
      patient: patient,
      expires_at: 5.minutes.ago
    )

    expect(summary.total_slots).to eq(4)
    expect(summary.booked_slots).to eq(0)
    expect(summary.held_slots).to eq(0)
    expect(summary.available_slots).to eq(4)
  end
end
