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
  it "allows a different clinician of the same type" do
    other_clinician = create(:staff_member, practice: practice, staff_type: appointment.clinician.staff_type)
    replacement.update!(clinician: other_clinician,
      availability_block: create(:availability_block, practice: practice, clinician: other_clinician))
    described_class.new(appointment: appointment, replacement_slot: replacement, staff_user: staff_user).call
    expect(appointment.reload.clinician).to eq(other_clinician)
  end

  it "does not permit a different practice" do
    other_practice = create(:practice)
    other_clinician = create(:staff_member, practice: other_practice, staff_type: appointment.clinician.staff_type)
    replacement.update!(practice: other_practice, clinician: other_clinician,
      availability_block: create(:availability_block, practice: other_practice, clinician: other_clinician))
    expect {
      described_class.new(appointment: appointment, replacement_slot: replacement, staff_user: staff_user).call
    }.to raise_error(described_class::NotAllowed, /practice/)
  end

  it "rejects appointments which are not booked or confirmed" do
    appointment.update!(status: "arrived")
    expect {
      described_class.new(appointment: appointment, replacement_slot: replacement, staff_user: staff_user).call
    }.to raise_error(described_class::NotAllowed, /booked or confirmed/)
  end

  it "rejects a patient without approved access" do
    patient_account = create(:patient_account)
    expect {
      described_class.new(appointment: appointment, replacement_slot: replacement, patient_account: patient_account).call
    }.to raise_error(described_class::NotAllowed, /approved/)
  end

  it "rejects rescheduling within 24 hours for patients, even with approved access" do
    patient_account = create(:patient_account, confirmed_at: Time.current)
    PatientAccountLink.create!(patient_account: patient_account, patient: appointment.patient,
      practice: practice, status: "approved", approved_at: Time.current,
      verified_at: Time.current, verification_method: "in_person",
      verified_by: create(:staff_member, practice: practice, access_level: "staff_admin"))
    appointment.appointment_slot.update!(starts_at: 12.hours.from_now, ends_at: 12.hours.from_now + 20.minutes)
    expect {
      described_class.new(appointment: appointment, replacement_slot: replacement, patient_account: patient_account).call
    }.to raise_error(described_class::NotAllowed, /24 hours/)
  end

  it "allows staff to reschedule within 24 hours" do
    appointment.appointment_slot.update!(starts_at: 12.hours.from_now, ends_at: 12.hours.from_now + 20.minutes)
    described_class.new(appointment: appointment, replacement_slot: replacement, staff_user: staff_user).call
    expect(appointment.reload.appointment_slot).to eq(replacement)
  end

  it "rejects an active hold on the replacement slot" do
    create(:appointment_hold, appointment_slot: replacement,
      patient: appointment.patient, expires_at: 10.minutes.from_now)
    expect {
      described_class.new(appointment: appointment, replacement_slot: replacement, staff_user: staff_user).call
    }.to raise_error(described_class::NotAllowed, /available/)
  end

end
