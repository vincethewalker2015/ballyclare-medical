require "rails_helper"

RSpec.describe "Patient portal outstanding payments", type: :request do
  let(:account) { create(:patient_account, confirmed_at: Time.current) }
  let(:patient) { create(:patient) }
  let(:appointment) { create(:appointment, patient: patient, practice: patient.practice) }

  before do
    admin = create(:staff_member, practice: patient.practice, staff_type: "administrator", access_level: "staff_admin")
    PatientAccountLink.create!(patient_account: account, patient: patient, practice: patient.practice,
      status: "approved", verification_method: "in_person", verified_at: Time.current,
      verified_by: admin, approved_at: Time.current)
    allow(ENV).to receive(:fetch).with("STRIPE_PUBLISHABLE_KEY").and_return("pk_test_portal")
  end

  it "requires authentication and approved access" do
    get patient_portal_outstanding_payment_path(appointment)
    expect(response).to redirect_to(new_patient_account_session_path)
    account.patient_account_links.first.update!(status: "revoked")
    sign_in account, scope: :patient_account
    get patient_portal_outstanding_payment_path(appointment)
    expect(response).to have_http_status(:forbidden)
    expect(response.body).to include("Patient portal access unavailable")
    expect(Stripe::PaymentIntent).not_to receive(:create)
    post patient_portal_outstanding_payment_path(appointment)
    expect(response).to have_http_status(:forbidden)
    expect(response.body).to include("Patient portal access unavailable")
  end

  it "pays the current outstanding charge using the existing Stripe service" do
    create(:appointment_charge, appointment: appointment, patient: patient, practice: patient.practice,
      amount_cents: 6_500)
    sign_in account, scope: :patient_account
    intent = instance_double(Stripe::PaymentIntent, id: "pi_balance_test", client_secret: "pi_balance_secret")
    expect(Stripe::PaymentIntent).to receive(:create).once.and_return(intent)

    get patient_portal_outstanding_payment_path(appointment)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("£65.00")

    expect { post patient_portal_outstanding_payment_path(appointment) }.to change(Payment, :count).by(1)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("pi_balance_secret")
    payment = Payment.last
    expect(payment.appointment).to eq(appointment)
    expect(payment.amount_cents).to eq(6_500)
    expect(payment.currency).to eq(patient.practice.currency)
    expect(payment.status).to eq("processing")

    post patient_portal_outstanding_payment_path(appointment)
    expect(response).to redirect_to(patient_portal_outstanding_payment_path(appointment))
    expect(Payment.count).to eq(1)
  end

  it "recovers a pending payment with the original Stripe idempotency key" do
    create(:appointment_charge, appointment: appointment, patient: patient, practice: patient.practice,
      amount_cents: 6_500)
    pending = create(:payment, appointment: appointment, patient: patient,
      amount_cents: 6_500, status: "pending", provider_payment_id: nil)
    pending.update_columns(updated_at: 1.minute.ago)
    intent = instance_double(Stripe::PaymentIntent, id: "pi_recovered",
      client_secret: "pi_recovered_secret", status: "requires_payment_method")
    expect(Stripe::PaymentIntent).to receive(:create).with(
      hash_including(amount: 6_500), hash_including(idempotency_key: pending.idempotency_key)
    ).once.and_return(intent)
    sign_in account, scope: :patient_account

    expect { post patient_portal_outstanding_payment_path(appointment) }.not_to change(Payment, :count)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("pi_recovered_secret")
    expect(pending.reload.provider_payment_id).to eq("pi_recovered")
  end

  it "rejects another patient's and another practice's appointments before Stripe" do
    other = create(:appointment, patient: create(:patient, practice: patient.practice), practice: patient.practice)
    foreign_patient = create(:patient, practice: create(:practice))
    foreign = create(:appointment, patient: foreign_patient, practice: foreign_patient.practice)
    sign_in account, scope: :patient_account
    expect(Stripe::PaymentIntent).not_to receive(:create)
    [ other, foreign ].each do |record|
      sign_in account, scope: :patient_account
      get patient_portal_outstanding_payment_path(record)
      expect(response).to have_http_status(:not_found)
      sign_in account, scope: :patient_account
      post patient_portal_outstanding_payment_path(record)
      expect(response).to have_http_status(:not_found)
    end
  end

  it "does not charge a zero balance or cancelled appointment" do
    sign_in account, scope: :patient_account
    expect(Stripe::PaymentIntent).not_to receive(:create)
    post patient_portal_outstanding_payment_path(appointment)
    expect(response).to redirect_to(patient_portal_outstanding_payment_path(appointment))
    create(:appointment_charge, appointment: appointment, patient: patient, practice: patient.practice)
    appointment.update!(status: "cancelled")
    post patient_portal_outstanding_payment_path(appointment)
    expect(response).to redirect_to(patient_portal_outstanding_payment_path(appointment))
    expect(Payment.count).to eq(0)
  end

  it "blocks a second attempt when a pending payment exists" do
    create(:appointment_charge, appointment: appointment, patient: patient, practice: patient.practice)
    create(:payment, appointment: appointment, patient: patient, status: "pending")
    sign_in account, scope: :patient_account
    expect(Stripe::PaymentIntent).not_to receive(:create)
    post patient_portal_outstanding_payment_path(appointment)
    expect(response).to redirect_to(patient_portal_outstanding_payment_path(appointment))
    expect(Payment.count).to eq(1)
  end
end
