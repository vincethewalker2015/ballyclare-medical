require "rails_helper"

RSpec.describe "Patient portal appointment history", type: :request do
  let(:account) { create(:patient_account, confirmed_at: Time.current) }

  def approve(patient)
    administrator = create(:staff_member, practice: patient.practice,
      staff_type: "administrator", access_level: "staff_admin")
    PatientAccountLink.create!(
      patient_account: account, patient: patient, practice: patient.practice,
      status: "approved", verification_method: "in_person",
      verified_at: Time.current, verified_by: administrator, approved_at: Time.current
    )
  end

  it "requires authentication and an approved link" do
    get patient_portal_appointment_history_path
    expect(response).to redirect_to(new_patient_account_session_path)

    sign_in account, scope: :patient_account
    get patient_portal_appointment_history_path
    expect(response).to have_http_status(:forbidden)
  end

  it "shows upcoming, completed and cancelled visits but not another patient's records" do
    patient = create(:patient)
    approve(patient)
    upcoming = create(:appointment, patient: patient, practice: patient.practice, status: "booked")
    completed = create(:appointment, patient: patient, practice: patient.practice, status: "completed")
    cancelled = create(:appointment, patient: patient, practice: patient.practice, status: "cancelled")
    other = create(:appointment, patient: create(:patient, practice: patient.practice),
      practice: patient.practice, status: "booked")
    [ [upcoming, 3], [completed, -3], [cancelled, 5], [other, 8] ].each do |appointment, days|
      starts_at = days.days.from_now
      appointment.appointment_slot.update!(starts_at: starts_at, ends_at: starts_at + 20.minutes)
    end

    sign_in account, scope: :patient_account
    get patient_portal_appointment_history_path
    expect(response).to have_http_status(:ok)
    [ upcoming, completed, cancelled ].each do |appointment|
      expect(response.body).to include(
        appointment.appointment_slot.starts_at.in_time_zone(patient.practice.timezone)
          .strftime("%A %-d %B %Y, %-I:%M %p")
      )
    end
    expect(response.body).not_to include(other.appointment_slot.starts_at
      .in_time_zone(patient.practice.timezone).strftime("%A %-d %B %Y, %-I:%M %p"))
    expect(response.body).to include("Completed", "Cancelled")
  end

  it "removes access immediately when the patient link is revoked" do
    patient = create(:patient)
    link = approve(patient)
    sign_in account, scope: :patient_account
    get patient_portal_appointment_history_path
    expect(response).to have_http_status(:ok)

    link.update!(status: "revoked")
    get patient_portal_appointment_history_path
    expect(response).to have_http_status(:forbidden)
  end

  it "does not expose appointments in another practice" do
    patient = create(:patient)
    approve(patient)
    foreign = create(:appointment, patient: create(:patient, practice: create(:practice)))
    foreign.appointment_slot.update!(starts_at: 9.days.from_now, ends_at: 9.days.from_now + 20.minutes)
    sign_in account, scope: :patient_account

    get patient_portal_appointment_history_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(foreign.appointment_slot.starts_at
      .in_time_zone(patient.practice.timezone).strftime("%A %-d %B %Y, %-I:%M %p"))
  end
end
