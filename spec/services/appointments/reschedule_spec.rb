require "rails_helper"

RSpec.describe Appointments::Reschedule do
  let(:appointment) { create(:appointment, status: "booked") }
  let(:practice) { appointment.practice }
  let(:staff_user) { create(:user) }
  let(:replacement) do
    create(:appointment_slot, practice: practice, clinician: appointment.clinician,
      availability_block: appointment.appointment_slot.availability_block,
      starts_at: appointment.appointment_slot.starts_at + 20.minutes,
      ends_at: appointment.appointment_slot.starts_at + 40.minutes)
  end

  before do
    appointment.appointment_slot.update!(starts_at: 1.day.from_now.change(hour: 10, min: 0),
      ends_at: 1.day.from_now.change(hour: 10, min: 20))
  end

  it "moves an appointment without changing its identity and audits the change" do
    expect {
      described_class.new(appointment: appointment, replacement_slot: replacement, staff_user: staff_user).call
    }.to change(AuditEvent, :count).by(1)
    expect(appointment.reload.appointment_slot).to eq(replacement)
    expect(AuditEvent.last.metadata["old_slot_id"]).to be_present
  end

  it "rejects a different clinician type" do
    other_clinician = create(:staff_member, practice: practice,
      staff_type: appointment.clinician.staff_type == "doctor" ? "nurse" : "doctor")
    replacement.update!(clinician: other_clinician,
      availability_block: create(:availability_block, practice: practice, clinician: other_clinician))
    expect {
      described_class.new(appointment: appointment, replacement_slot: replacement, staff_user: staff_user).call
    }.to raise_error(described_class::NotAllowed, /type/)
  end

  it "rejects a booked replacement slot" do
    create(:appointment, practice: practice, appointment_slot: replacement, clinician: replacement.clinician)
    expect {
      described_class.new(appointment: appointment, replacement_slot: replacement, staff_user: staff_user).call
    }.to raise_error(described_class::NotAllowed, /available/)
  end

  it "rejects a replacement in the past" do
    replacement.update!(starts_at: 1.day.ago, ends_at: 1.day.ago + 30.minutes)
    expect {
      described_class.new(appointment: appointment, replacement_slot: replacement, staff_user: staff_user).call
    }.to raise_error(described_class::NotAllowed, /future/)
  end
end
