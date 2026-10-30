require "rails_helper"

RSpec.describe "Patient portal appointment rescheduling", type: :request do
  let(:account) { create(:patient_account, confirmed_at: Time.current) }
  let(:patient) { create(:patient) }
  let(:appointment) { create(:appointment, patient: patient, practice: patient.practice, status: "booked") }
  let(:replacement) do
    create(:appointment_slot, practice: patient.practice, clinician: appointment.clinician,
      availability_block: appointment.appointment_slot.availability_block,
      starts_at: appointment.appointment_slot.starts_at + 20.minutes,
      ends_at: appointment.appointment_slot.starts_at + 40.minutes)
  end

  before do
    administrator = create(:staff_member, practice: patient.practice,
      staff_type: "administrator", access_level: "staff_admin")
    PatientAccountLink.create!(patient_account: account, patient: patient, practice: patient.practice,
      status: "approved", verification_method: "in_person", verified_at: Time.current,
      verified_by: administrator, approved_at: Time.current)
    appointment.appointment_slot.update!(starts_at: 3.days.from_now, ends_at: 3.days.from_now + 20.minutes)
  end

  it "requires authentication" do
    patch patient_portal_appointment_reschedule_path(appointment), params: { appointment_slot_id: replacement.id }
    expect(response).to redirect_to(new_patient_account_session_path)
    expect(appointment.reload.appointment_slot_id).not_to eq(replacement.id)
  end

  it "shows eligible replacement slots" do
    sign_in account, scope: :patient_account
    get edit_patient_portal_appointment_reschedule_path(appointment)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Reschedule appointment")
  end

  it "reschedules and records an audit event" do
    sign_in account, scope: :patient_account
    expect {
      patch patient_portal_appointment_reschedule_path(appointment), params: { appointment_slot_id: replacement.id }
    }.to change(AuditEvent, :count).by(1)
    expect(response).to redirect_to(patient_portal_appointment_history_path)
    expect(appointment.reload.appointment_slot_id).to eq(replacement.id)
    expect(AuditEvent.last.metadata["actor_type"]).to eq("patient")
  end

  it "does not reschedule another patient's appointment" do
    foreign = create(:appointment, practice: patient.practice,
      patient: create(:patient, practice: patient.practice))
    sign_in account, scope: :patient_account
    patch patient_portal_appointment_reschedule_path(foreign), params: { appointment_slot_id: replacement.id }
    expect(response).to have_http_status(:not_found)
  end

  it "rejects revoked patient access" do
    account.patient_account_links.first.update!(status: "revoked")
    sign_in account, scope: :patient_account
    patch patient_portal_appointment_reschedule_path(appointment), params: { appointment_slot_id: replacement.id }
    expect(response).to have_http_status(:forbidden)
  end

  it "rejects changes within 24 hours" do
    appointment.appointment_slot.update!(starts_at: 12.hours.from_now, ends_at: 12.hours.from_now + 20.minutes)
    sign_in account, scope: :patient_account
    patch patient_portal_appointment_reschedule_path(appointment), params: { appointment_slot_id: replacement.id }
    expect(response).to redirect_to(edit_patient_portal_appointment_reschedule_path(appointment))
    expect(appointment.reload.appointment_slot_id).not_to eq(replacement.id)
  end

  it "rejects a slot belonging to another practice" do
    foreign_slot = create(:appointment_slot)
    sign_in account, scope: :patient_account
    patch patient_portal_appointment_reschedule_path(appointment), params: { appointment_slot_id: foreign_slot.id }
    expect(response).to have_http_status(:not_found)
  end
end
