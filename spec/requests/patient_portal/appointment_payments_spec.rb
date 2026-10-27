require "rails_helper"

RSpec.describe "Patient portal hold payments", type: :request do
  let(:account) { create(:patient_account, confirmed_at: Time.current) }
  let(:patient) { create(:patient) }
  let(:slot) do
    clinician = create(:staff_member, practice: patient.practice, staff_type: "doctor")
    appointment_slot = create(:appointment_slot, practice: patient.practice, clinician: clinician)
    appointment_slot.availability_block.update!(bookable_online: true)
    appointment_slot
  end

  before do
    allow(ENV).to receive(:fetch).with("STRIPE_PUBLISHABLE_KEY").and_return("pk_test_patient_portal")
    administrator = create(:staff_member, practice: patient.practice, staff_type: "administrator", access_level: "staff_admin")
    PatientAccountLink.create!(patient_account: account, patient: patient, practice: patient.practice,
      status: "approved", verification_method: "in_person", verified_at: Time.current,
      verified_by: administrator, approved_at: Time.current)
    create(:consultation_fee, practice: patient.practice, clinician_type: "doctor")
  end

  it "creates a payment for the configured consultation fee, not an appointment" do
    hold = slot.hold_for!(patient: patient)
    sign_in account, scope: :patient_account
    intent = instance_double(Stripe::PaymentIntent, id: "pi_patient_test", client_secret: "pi_secret_test")
    allow(Stripe::PaymentIntent).to receive(:create).and_return(intent)

    expect {
      post patient_portal_appointment_hold_payment_path(hold)
    }.to change(Payment, :count).by(1).and change(Appointment, :count).by(0)

    payment = Payment.last
    expect(payment.patient).to eq(patient)
    expect(payment.appointment_hold).to eq(hold)
    expect(payment.amount_cents).to eq(6_500)
    expect(payment.currency).to eq(patient.practice.currency)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pay for your appointment")
  end

  it "does not initiate two payments for the same reservation" do
    hold = slot.hold_for!(patient: patient)
    sign_in account, scope: :patient_account
    allow(Stripe::PaymentIntent).to receive(:create).and_return(
      instance_double(Stripe::PaymentIntent, id: "pi_patient_test", client_secret: "pi_secret_test")
    )
    post patient_portal_appointment_hold_payment_path(hold)
    post patient_portal_appointment_hold_payment_path(hold)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pay for your appointment")
    expect(Payment.count).to eq(1)
  end

  it "retries an interrupted Stripe request with the same idempotency key" do
    hold = slot.hold_for!(patient: patient)
    sign_in account, scope: :patient_account
    intent = instance_double(Stripe::PaymentIntent, id: "pi_patient_retry", client_secret: "pi_secret_retry")
    attempts = 0
    allow(Stripe::PaymentIntent).to receive(:create) do
      attempts += 1
      raise Stripe::APIConnectionError.new("Temporary Stripe connection failure") if attempts == 1
      intent
    end

    post patient_portal_appointment_hold_payment_path(hold)
    expect(response).to redirect_to(patient_portal_appointment_hold_path(hold))
    payment = Payment.last
    expect(payment.status).to eq("pending")

    post patient_portal_appointment_hold_payment_path(hold)
    expect(response).to have_http_status(:ok)
    expect(Payment.count).to eq(1)
    expect(payment.reload.provider_payment_id).to eq("pi_patient_retry")
  end

  it "refuses to charge an expired hold" do
    hold = slot.hold_for!(patient: patient)
    hold.update!(expires_at: 1.minute.ago)
    sign_in account, scope: :patient_account
    post patient_portal_appointment_hold_payment_path(hold)
    expect(response).to redirect_to(patient_portal_appointment_hold_path(hold))
    expect(Payment.count).to eq(0)
  end

  it "rejects payment initiation after the patient link is revoked" do
    hold = slot.hold_for!(patient: patient)
    account.patient_account_links.first.update!(status: "revoked")
    sign_in account, scope: :patient_account

    expect(Stripe::PaymentIntent).not_to receive(:create)
    expect {
      post patient_portal_appointment_hold_payment_path(hold)
    }.not_to change(Payment, :count)

    expect(response).to have_http_status(:forbidden)
  end

  it "rejects payment initiation without a patient link" do
    hold = slot.hold_for!(patient: patient)
    PatientAccountLink.where(patient_account: account).delete_all
    sign_in account, scope: :patient_account

    expect(Stripe::PaymentIntent).not_to receive(:create)
    expect {
      post patient_portal_appointment_hold_payment_path(hold)
    }.not_to change(Payment, :count)

    expect(response).to have_http_status(:forbidden)
  end

  it "does not disclose another patient's payment status by ID in the same practice" do
    other_patient = create(:patient, practice: patient.practice)
    other_appointment = create(:appointment, patient: other_patient, practice: patient.practice)
    other_payment = create(:payment, patient: other_patient, appointment: other_appointment)

    sign_in account, scope: :patient_account
    expect(Payments::ReconcileStripeStatus).not_to receive(:new)

    get patient_portal_payment_path(other_payment)

    expect(response).to have_http_status(:not_found)
  end

  it "blocks cross-practice hold and payment IDs without Stripe reconciliation" do
    foreign_patient = create(:patient, practice: create(:practice))
    foreign_slot = create(:appointment_slot, practice: foreign_patient.practice,
      clinician: create(:staff_member, practice: foreign_patient.practice))
    foreign_hold = create(:appointment_hold, patient: foreign_patient,
      appointment_slot: foreign_slot)
    foreign_appointment = create(:appointment, patient: foreign_patient,
      practice: foreign_patient.practice)
    foreign_payment = create(:payment, patient: foreign_patient,
      appointment: foreign_appointment)

    sign_in account, scope: :patient_account
    expect(Payments::ReconcileStripeStatus).not_to receive(:new)
    expect(Stripe::PaymentIntent).not_to receive(:create)

    get patient_portal_appointment_hold_path(foreign_hold)
    expect(response).to have_http_status(:not_found)

    get patient_portal_payment_path(foreign_payment)
    expect(response).to have_http_status(:not_found)

    expect {
      post patient_portal_appointment_hold_payment_path(foreign_hold)
    }.not_to change(Payment, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "rejects payments for another patient's reservation" do
    hold = slot.hold_for!(patient: patient)
    another_patient = create(:patient, practice: patient.practice)
    another_account = create(:patient_account, confirmed_at: Time.current)
    admin = create(:staff_member, practice: patient.practice, staff_type: "administrator", access_level: "staff_admin")
    PatientAccountLink.create!(patient_account: another_account, patient: another_patient,
      practice: patient.practice, status: "approved", verification_method: "in_person",
      verified_at: Time.current, verified_by: admin, approved_at: Time.current)
    sign_in another_account, scope: :patient_account
    post patient_portal_appointment_hold_payment_path(hold)
    expect(response).to have_http_status(:not_found)
    expect(Payment.count).to eq(0)
  end
end
