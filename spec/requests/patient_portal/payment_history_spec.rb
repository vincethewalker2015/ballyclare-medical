require "rails_helper"

RSpec.describe "Patient portal payment history", type: :request do
  let(:account) { create(:patient_account, confirmed_at: Time.current) }

  def approve(patient)
    admin = create(:staff_member, practice: patient.practice,
      staff_type: "administrator", access_level: "staff_admin")
    PatientAccountLink.create!(patient_account: account, patient: patient,
      practice: patient.practice, status: "approved",
      verification_method: "in_person", verified_at: Time.current,
      verified_by: admin, approved_at: Time.current)
  end

  it "requires sign-in and approved access" do
    get patient_portal_payment_history_path
    expect(response).to redirect_to(new_patient_account_session_path)
    sign_in account, scope: :patient_account
    get patient_portal_payment_history_path
    expect(response).to have_http_status(:forbidden)
    expect(response.body).to include("Patient portal access unavailable")
  end

  it "lists the patient's transactions and refunds without exposing other patients or practices" do
    patient = create(:patient)
    approve(patient)
    own = create(:payment, patient: patient, appointment: create(:appointment, patient: patient, practice: patient.practice),
      amount_cents: 6500, status: "succeeded")
    create(:refund, payment: own, amount_cents: 1000, status: "succeeded")
    other = create(:payment, patient: create(:patient, practice: patient.practice), amount_cents: 9876)
    foreign_patient = create(:patient, practice: create(:practice))
    foreign = create(:payment, patient: foreign_patient, appointment: create(:appointment, patient: foreign_patient, practice: foreign_patient.practice), amount_cents: 8765)
    sign_in account, scope: :patient_account

    get patient_portal_payment_history_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Patient portal · #{patient.first_name} #{patient.last_name}")
    expect(response.body).to include("£65.00", "£10.00", "£55.00", "View receipt")
    expect(response.body).not_to include("£98.76", "£87.65")
    get patient_portal_payment_receipt_path(own)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("£55.00")
    get patient_portal_payment_receipt_path(other)
    expect(response).to have_http_status(:not_found)
    get patient_portal_payment_receipt_path(foreign)
    expect(response).to have_http_status(:not_found)
  end

  it "does not issue receipts for unsuccessful payments" do
    patient = create(:patient)
    approve(patient)
    payment = create(:payment, patient: patient, status: "pending")
    sign_in account, scope: :patient_account
    get patient_portal_payment_receipt_path(payment)
    expect(response).to have_http_status(:not_found)
  end

  it "immediately revokes payment history and receipt access" do
    patient = create(:patient)
    link = approve(patient)
    appointment = create(:appointment, patient: patient, practice: patient.practice)
    payment = create(:payment, patient: patient, appointment: appointment, status: "succeeded")
    sign_in account, scope: :patient_account
    get patient_portal_payment_receipt_path(payment)
    expect(response).to have_http_status(:ok)
    link.update!(status: "revoked")
    get patient_portal_payment_history_path
    expect(response).to have_http_status(:forbidden)
    expect(response.body).to include("Patient portal access unavailable")
    get patient_portal_payment_receipt_path(payment)
    expect(response).to have_http_status(:forbidden)
    expect(response.body).to include("Patient portal access unavailable")
  end
end
