require "rails_helper"

RSpec.describe "Patient portal appointment discovery", type: :request do
  let(:account) { create(:patient_account, confirmed_at: Time.current) }

  def approve(patient)
    administrator = create(:staff_member, practice: patient.practice, staff_type: "administrator", access_level: "staff_admin")
    PatientAccountLink.create!(
      patient_account: account, patient: patient, practice: patient.practice,
      status: "approved", verification_method: "in_person",
      verified_at: Time.current, verified_by: administrator, approved_at: Time.current
    )
  end

  def online_slot(practice:, clinician:, day: 3, online: true)
    starts_at = day.days.from_now.change(hour: 10, min: 0)
    block = create(:availability_block, practice: practice, clinician: clinician,
      starts_at: starts_at - 1.hour, ends_at: starts_at + 1.hour, bookable_online: online)
    create(:appointment_slot, practice: practice, clinician: clinician,
      availability_block: block, starts_at: starts_at, ends_at: starts_at + 20.minutes)
  end

  it "requires authentication" do
    get patient_portal_appointments_path
    expect(response).to redirect_to(new_patient_account_session_path)
  end

  it "rejects unapproved and revoked patient accounts" do
    patient = create(:patient)
    sign_in account, scope: :patient_account
    get patient_portal_appointments_path
    expect(response).to have_http_status(:forbidden)

    link = approve(patient)
    link.update!(status: "revoked")
    get patient_portal_appointments_path
    expect(response).to have_http_status(:forbidden)
  end

  it "shows only online, unbooked, unheld slots in the linked practice" do
    patient = create(:patient)
    approve(patient)
    clinician = create(:staff_member, practice: patient.practice)
    available = online_slot(practice: patient.practice, clinician: clinician, day: 3)
    offline = online_slot(practice: patient.practice, clinician: clinician, day: 4, online: false)
    held = online_slot(practice: patient.practice, clinician: clinician, day: 5)
    create(:appointment_hold, appointment_slot: held, patient: patient, expires_at: 10.minutes.from_now)
    booked = online_slot(practice: patient.practice, clinician: clinician, day: 6)
    create(:appointment, practice: patient.practice, patient: patient, clinician: clinician, appointment_slot: booked)
    other_practice = create(:practice)
    other_clinician = create(:staff_member, practice: other_practice)
    foreign = online_slot(practice: other_practice, clinician: other_clinician, day: 7)

    sign_in account, scope: :patient_account
    get patient_portal_appointments_path, params: { clinician_id: clinician.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(available.starts_at.in_time_zone(patient.practice.timezone).strftime("%A %-d %B %Y"))
    [offline, held, booked, foreign].each do |slot|
      expect(response.body).not_to include(slot.starts_at.in_time_zone(slot.practice.timezone).strftime("%A %-d %B %Y"))
    end
    expect(AppointmentHold.where(appointment_slot: available)).to be_empty
  end

  it "does not reveal another practice's clinician through an ID parameter" do
    patient = create(:patient)
    approve(patient)
    other_practice = create(:practice)
    other_clinician = create(:staff_member, practice: other_practice)
    online_slot(practice: other_practice, clinician: other_clinician)

    sign_in account, scope: :patient_account
    get patient_portal_appointments_path, params: { clinician_id: other_clinician.id }
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(other_clinician.full_name)
    expect(response.body).to include("Choose a clinician")
  end
end
