require "rails_helper"

RSpec.describe "Patient portal dashboard", type: :request do
  let(:account) { create(:patient_account, :confirmed) }

  def approved_link(account:, patient:)
    administrator = create(:staff_member, practice: patient.practice, staff_type: "admin")
    allow(administrator).to receive(:staff_administration_access?).and_return(true)
    # Persist an approved, verified link through its normal model validations.
    PatientAccountLink.create!(
      patient_account: account, patient: patient, practice: patient.practice,
      status: "approved", verification_method: "in_person",
      verified_at: Time.current, verified_by: administrator, approved_at: Time.current
    )
  end

  it "redirects unauthenticated visitors" do
    get patient_portal_path
    expect(response).to redirect_to(new_patient_account_session_path)
  end

  it "does not expose patient details without an approved link" do
    sign_in account, scope: :patient_account
    get patient_portal_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Account verification pending")
    expect(response.body).not_to include("Outstanding balances")
  end

  it "shows only the approved patient's upcoming appointments" do
    patient = create(:patient)
    other_patient = create(:patient, practice: patient.practice)
    approved_link(account: account, patient: patient)
    appointment = create(:appointment, patient: patient, practice: patient.practice)
    other_appointment = create(:appointment, patient: other_patient, practice: patient.practice)
    appointment.appointment_slot.update!(starts_at: 3.days.from_now, ends_at: 3.days.from_now + 30.minutes)
    other_appointment.appointment_slot.update!(starts_at: 4.days.from_now, ends_at: 4.days.from_now + 30.minutes)

    sign_in account, scope: :patient_account
    get patient_portal_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(appointment.appointment_slot.starts_at.in_time_zone(patient.practice.timezone).strftime("%-d %B %Y"))
    expect(response.body).not_to include(other_appointment.appointment_slot.starts_at.in_time_zone(patient.practice.timezone).strftime("%-d %B %Y"))
  end
end
