require "rails_helper"

RSpec.describe "Patient portal appointment reservations", type: :request do
  let(:account) { create(:patient_account, confirmed_at: Time.current) }

  def approve(patient)
    administrator = create(:staff_member, practice: patient.practice, staff_type: "administrator", access_level: "staff_admin")
    PatientAccountLink.create!(
      patient_account: account, patient: patient, practice: patient.practice,
      status: "approved", verification_method: "in_person",
      verified_at: Time.current, verified_by: administrator, approved_at: Time.current
    )
  end

  def slot_for(patient, online: true)
    clinician = create(:staff_member, practice: patient.practice)
    slot = create(:appointment_slot, practice: patient.practice, clinician: clinician)
    slot.availability_block.update!(bookable_online: online)
    slot
  end

  it "requires authentication to reserve a time" do
    patient = create(:patient)
    slot = slot_for(patient)
    post patient_portal_appointment_holds_path, params: { appointment_slot_id: slot.id }
    expect(response).to redirect_to(new_patient_account_session_path)
    expect(AppointmentHold.count).to eq(0)
  end

  it "forbids accounts without an approved patient link" do
    patient = create(:patient)
    slot = slot_for(patient)
    sign_in account, scope: :patient_account
    post patient_portal_appointment_holds_path, params: { appointment_slot_id: slot.id }
    expect(response).to have_http_status(:forbidden)
    expect(AppointmentHold.count).to eq(0)
  end

  it "holds an online slot without creating an unpaid appointment" do
    patient = create(:patient)
    approve(patient)
    slot = slot_for(patient)
    sign_in account, scope: :patient_account

    expect {
      post patient_portal_appointment_holds_path, params: { appointment_slot_id: slot.id }
    }.to change(AppointmentHold, :count).by(1).and change(Appointment, :count).by(0)
    hold = AppointmentHold.last
    expect(hold.patient).to eq(patient)
    expect(hold.expires_at).to be_within(2.seconds).of(10.minutes.from_now)
    expect(response).to redirect_to(patient_portal_appointment_hold_path(hold))
    get patient_portal_appointment_hold_path(hold)
    expect(response.body).to include("Your appointment selection")
    expect(response.body).to include("not booked yet")
  end

  it "does not allow another account to access the hold" do
    patient = create(:patient)
    approve(patient)
    slot = slot_for(patient)
    hold = slot.hold_for!(patient: patient)
    other_account = create(:patient_account, confirmed_at: Time.current)
    other_patient = create(:patient, practice: patient.practice)
    administrator = create(:staff_member, practice: patient.practice, staff_type: "administrator", access_level: "staff_admin")
    PatientAccountLink.create!(patient_account: other_account, patient: other_patient,
      practice: patient.practice, status: "approved", verification_method: "in_person",
      verified_at: Time.current, verified_by: administrator, approved_at: Time.current)
    sign_in other_account, scope: :patient_account
    get patient_portal_appointment_hold_path(hold)
    expect(response).to have_http_status(:not_found)
  end

  it "rejects offline slots and cross-practice slot identifiers" do
    patient = create(:patient)
    approve(patient)
    offline = slot_for(patient, online: false)
    foreign = slot_for(create(:patient))
    sign_in account, scope: :patient_account
    [ offline, foreign ].each do |slot|
      post patient_portal_appointment_holds_path, params: { appointment_slot_id: slot.id }
      expect(response).to redirect_to(patient_portal_appointments_path)
    end
    expect(AppointmentHold.count).to eq(0)
  end

  it "does not create a second active reservation for the same slot" do
    patient = create(:patient)
    approve(patient)
    slot = slot_for(patient)
    sign_in account, scope: :patient_account
    post patient_portal_appointment_holds_path, params: { appointment_slot_id: slot.id }
    post patient_portal_appointment_holds_path, params: { appointment_slot_id: slot.id }
    expect(response).to redirect_to(patient_portal_appointments_path)
    expect(AppointmentHold.count).to eq(1)
  end

  it "rejects reservations when the approved link is revoked" do
    patient = create(:patient)
    link = approve(patient)
    slot = slot_for(patient)
    link.update!(status: "revoked")
    sign_in account, scope: :patient_account
    post patient_portal_appointment_holds_path, params: { appointment_slot_id: slot.id }
    expect(response).to have_http_status(:forbidden)
    expect(AppointmentHold.count).to eq(0)
  end
end
