require "rails_helper"

RSpec.describe Appointments::Reschedule do
  let(:appointment) { create(:appointment, status: "booked") }
  let(:practice) { appointment.practice }
  let(:account) { create(:patient_account) }
  let(:staff_user) { create(:user) }
  let(:replacement) { create(:appointment_slot, practice: practice, clinician: appointment.clinician, starts_at: 4.days.from_now, ends_at: 4.days.from_now + 30.minutes) }

  before do
    appointment.appointment_slot.update!(starts_at: 3.days.from_now, ends_at: 3.days.from_now + 30.minutes)
  end

  it "moves an appointment without changing its identity and audits the change" do
    expect {
      described_class.new(appointment: appointment, replacement_slot: replacement, staff_user: staff_user).call
    }.to change(AuditEvent, :count).by(1)
    expect(appointment.reload.appointment_slot).to eq(replacement)
    expect(AuditEvent.last.metadata["old_slot_id"]).to be_present
  end

  it "rejects a different clinician type" do
    replacement.clinician.update!(staff_type: appointment.clinician.staff_type == "doctor" ? "nurse" : "doctor")
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
