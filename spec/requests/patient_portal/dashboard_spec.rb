require "rails_helper"

RSpec.describe "Patient portal dashboard", type: :request do
  let(:account) { create(:patient_account, confirmed_at: Time.current) }

  def approved_link(account:, patient:)
    administrator = create(:staff_member, practice: patient.practice, staff_type: "administrator", access_level: "staff_admin")
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
  it "immediately hides records when an approved link is revoked" do
    patient = create(:patient)
    link = approved_link(account: account, patient: patient)
    appointment = create(:appointment, patient: patient, practice: patient.practice)
    appointment.appointment_slot.update!(starts_at: 6.days.from_now, ends_at: 6.days.from_now + 30.minutes)
    create(:appointment_charge, appointment: appointment, amount_cents: 6500)

    sign_in account, scope: :patient_account
    get patient_portal_path
    expect(response.body).to include("GBP 65.00")

    link.update!(status: "revoked")
    get patient_portal_path
    expect(response.body).to include("Account verification pending")
    expect(response.body).not_to include("GBP 65.00")
    expect(response.body).not_to include("Upcoming appointments")
  end

  it "excludes cancelled and completed appointments from upcoming visits" do
    patient = create(:patient)
    approved_link(account: account, patient: patient)
    booked = create(:appointment, patient: patient, practice: patient.practice, status: "booked")
    cancelled = create(:appointment, patient: patient, practice: patient.practice, status: "cancelled")
    completed = create(:appointment, patient: patient, practice: patient.practice, status: "completed")
    [booked, cancelled, completed].each_with_index do |appointment, index|
      starts_at = (index + 2).days.from_now
      appointment.appointment_slot.update!(starts_at: starts_at, ends_at: starts_at + 30.minutes)
    end

    sign_in account, scope: :patient_account
    get patient_portal_path
    expect(response.body).to include(booked.appointment_slot.starts_at.in_time_zone(patient.practice.timezone).strftime("%-d %B %Y"))
    [cancelled, completed].each do |appointment|
      expect(response.body).not_to include(appointment.appointment_slot.starts_at.in_time_zone(patient.practice.timezone).strftime("%-d %B %Y"))
    end
  end

  it "calculates balances from charges, partial payments and successful refunds even for completed visits" do
    patient = create(:patient)
    approved_link(account: account, patient: patient)
    appointment = create(:appointment, patient: patient, practice: patient.practice, status: "completed")
    create(:appointment_charge, appointment: appointment, amount_cents: 6500)
    payment = create(:payment, appointment: appointment, amount_cents: 4000, status: "succeeded")
    create(:refund, payment: payment, amount_cents: 1000, status: "succeeded")

    sign_in account, scope: :patient_account
    get patient_portal_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("GBP 35.00")
    expect(response.body).not_to include("GBP 25.00")
  end

  it "does not display another practice's appointments or balances" do
    patient = create(:patient)
    approved_link(account: account, patient: patient)
    other_patient = create(:patient, practice: create(:practice))
    other_appointment = create(:appointment, patient: other_patient, practice: other_patient.practice)
    create(:appointment_charge, appointment: other_appointment, amount_cents: 9876)
    other_appointment.appointment_slot.update!(starts_at: 7.days.from_now, ends_at: 7.days.from_now + 30.minutes)

    sign_in account, scope: :patient_account
    get patient_portal_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("GBP 98.76")
    expect(response.body).not_to include(other_appointment.appointment_slot.starts_at.in_time_zone(other_patient.practice.timezone).strftime("%-d %B %Y"))
  end

end
