require "rails_helper"

RSpec.describe "Patient portal appointment cancellation", type: :request do
  let(:account) { create(:patient_account, confirmed_at: Time.current) }
  let(:patient) { create(:patient) }
  let(:appointment) { create(:appointment, patient: patient, practice: patient.practice, status: "booked") }

  before do
    admin = create(:staff_member, practice: patient.practice,
      staff_type: "administrator", access_level: "staff_admin")
    PatientAccountLink.create!(patient_account: account, patient: patient, practice: patient.practice,
      status: "approved", verification_method: "in_person", verified_at: Time.current,
      verified_by: admin, approved_at: Time.current)
    appointment.appointment_slot.update!(starts_at: 3.days.from_now, ends_at: 3.days.from_now + 20.minutes)
  end

  it "requires authentication" do
    patch patient_portal_cancel_appointment_path(appointment)
    expect(response).to redirect_to(new_patient_account_session_path)
  end

  it "cancels an eligible appointment, voids charges and requests a full refund" do
    charge = create(:appointment_charge, appointment: appointment, patient: patient,
      practice: patient.practice, amount_cents: 6500, status: "active")
    payment = create(:payment, appointment: appointment, patient: patient,
      status: "succeeded", amount_cents: 6500)
    sign_in account, scope: :patient_account

    expect { patch patient_portal_cancel_appointment_path(appointment) }.to change(Refund, :count).by(1)
    expect(response).to redirect_to(patient_portal_appointment_history_path)
    expect(appointment.reload.status).to eq("cancelled")
    expect(charge.reload.status).to eq("voided")
    expect(payment.refunds.last.amount_cents).to eq(6500)
    expect(appointment.appointment_status_changes.last).to have_attributes(
      changed_by: nil, from_status: "booked", to_status: "cancelled"
    )
    expect(appointment.appointment_status_changes.last.notes).to include(account.id)
  end

  it "rejects cancellations with less than 24 hours notice" do
    appointment.appointment_slot.update!(starts_at: 23.hours.from_now, ends_at: 24.hours.from_now)
    sign_in account, scope: :patient_account
    patch patient_portal_cancel_appointment_path(appointment)
    expect(appointment.reload.status).to eq("booked")
    expect(response).to redirect_to(patient_portal_appointment_history_path)
  end

  it "rejects cancellation after arrival" do
    appointment.update!(status: "arrived")
    sign_in account, scope: :patient_account
    patch patient_portal_cancel_appointment_path(appointment)
    expect(appointment.reload.status).to eq("arrived")
  end

  it "does not cancel another patient's appointment" do
    foreign = create(:appointment, patient: create(:patient, practice: patient.practice),
      practice: patient.practice)
    sign_in account, scope: :patient_account
    patch patient_portal_cancel_appointment_path(foreign)
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.status).to eq("booked")
  end

  it "rejects cancellation while a payment is pending" do
    create(:payment, appointment: appointment, patient: patient, status: "pending")
    sign_in account, scope: :patient_account
    patch patient_portal_cancel_appointment_path(appointment)
    expect(appointment.reload.status).to eq("booked")
  end

  it "rejects revoked access" do
    account.patient_account_links.first.update!(status: "revoked")
    sign_in account, scope: :patient_account
    patch patient_portal_cancel_appointment_path(appointment)
    expect(response).to have_http_status(:forbidden)
    expect(appointment.reload.status).to eq("booked")
  end
end
