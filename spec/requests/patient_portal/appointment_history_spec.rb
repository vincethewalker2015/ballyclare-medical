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
    expect(response.body).to include("Patient portal access unavailable")
  end

  it "shows upcoming, completed and cancelled visits but not another patient's records" do
    patient = create(:patient)
    approve(patient)
    upcoming = create(:appointment, patient: patient, practice: patient.practice, status: "booked")
    completed = create(:appointment, patient: patient, practice: patient.practice, status: "completed")
    cancelled = create(:appointment, patient: patient, practice: patient.practice, status: "cancelled")
    other = create(:appointment, patient: create(:patient, practice: patient.practice),
      practice: patient.practice, status: "booked")
    [ [ upcoming, 3 ], [ completed, -3 ], [ cancelled, 5 ], [ other, 8 ] ].each do |appointment, days|
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
    expect(response.body).to include("Patient portal access unavailable")
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
  it "shows pending and completed refunds with a live-update subscription" do
    patient = create(:patient)
    approve(patient)
    appointment = create(:appointment, patient: patient, practice: patient.practice, status: "cancelled")
    payment = create(:payment, appointment: appointment, patient: patient, status: "succeeded")
    refund = create(:refund, payment: payment, status: "pending")
    sign_in account, scope: :patient_account

    get patient_portal_appointment_history_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Refund pending", "turbo-cable-stream-source")\n    expect(response.body.scan("turbo-cable-stream-source").size).to eq(1)

    refund.update!(status: "succeeded")
    get patient_portal_appointment_history_path
    expect(response.body).to include("Refund completed")
    expect(response.body).not_to include("Refund pending")
  end

  it "instructs patients to contact the practice when a refund fails" do
    patient = create(:patient)
    approve(patient)
    appointment = create(:appointment, patient: patient, practice: patient.practice, status: "cancelled")
    payment = create(:payment, appointment: appointment, patient: patient, status: "succeeded")
    create(:refund, payment: payment, status: "failed")
    sign_in account, scope: :patient_account

    get patient_portal_appointment_history_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Refund failed", "contact your practice")
  end
  it "distinguishes a partial refund from a fully completed refund" do
    patient = create(:patient)
    approve(patient)
    appointment = create(:appointment, patient: patient, practice: patient.practice, status: "cancelled")
    payment = create(:payment, appointment: appointment, patient: patient,
      status: "succeeded", amount_cents: 6500)
    create(:refund, payment: payment, status: "succeeded", amount_cents: 2000)
    sign_in account, scope: :patient_account

    get patient_portal_appointment_history_path
    expect(response.body).to include("Partially refunded")
    expect(response.body).not_to include("Refund completed")

    create(:refund, payment: payment, status: "succeeded", amount_cents: 4500)
    get patient_portal_appointment_history_path
    expect(response.body).to include("Refund completed")
    expect(response.body).not_to include("Partially refunded")
  end

end
