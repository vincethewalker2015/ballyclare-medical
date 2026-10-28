require "rails_helper"

RSpec.describe "Patient portal checkout during a declared Stripe outage", type: :request do
  let(:account) { create(:patient_account, confirmed_at: Time.current) }
  let(:patient) { create(:patient) }
  let(:slot) do
    clinician = create(:staff_member, practice: patient.practice, staff_type: "doctor")
    appointment_slot = create(:appointment_slot, practice: patient.practice, clinician: clinician)
    appointment_slot.availability_block.update!(bookable_online: true)
    appointment_slot
  end

  before do
    administrator = create(:staff_member, practice: patient.practice,
      staff_type: "administrator", access_level: "staff_admin")
    PatientAccountLink.create!(
      patient_account: account, patient: patient, practice: patient.practice,
      status: "approved", verification_method: "in_person",
      verified_at: Time.current, verified_by: administrator, approved_at: Time.current
    )
    create(:consultation_fee, practice: patient.practice, clinician_type: "doctor")
  end

  it "offers pay-later booking instead of Stripe checkout for an approved patient during a declared outage" do
    hold = slot.hold_for!(patient: patient)
    senior = create(:staff_member, practice: patient.practice,
      staff_type: "administrator", access_level: "senior_staff_admin")
    Payments::StripeOutageDeclaration.activate!(
      practice: patient.practice, actor: senior, reason: "Stripe outage independently confirmed"
    )

    sign_in account, scope: :patient_account
    get patient_portal_appointment_hold_path(hold)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Book now — pay later")
    expect(response.body).to include("payment remains outstanding")
    expect(response.body).not_to include("Continue to secure payment")
    expect(Payment.count).to eq(0)
    expect(Appointment.count).to eq(0)
  end
  it "books an approved patient's held slot as unpaid without contacting Stripe during a declared outage" do
    hold = slot.hold_for!(patient: patient)
    senior = create(:staff_member, practice: patient.practice,
      staff_type: "administrator", access_level: "senior_staff_admin")
    Payments::StripeOutageDeclaration.activate!(
      practice: patient.practice, actor: senior, reason: "Stripe outage independently confirmed"
    )

    sign_in account, scope: :patient_account
    expect(Stripe::PaymentIntent).not_to receive(:create)

    expect {
      post "/patient-portal/appointment-holds/#{hold.id}/emergency-unpaid"
    }.to change(Appointment, :count).by(1)
      .and change(Payment, :count).by(0)
      .and change(AppointmentCharge, :count).by(1)

    appointment = Appointment.order(:created_at, :id).last
    expect(appointment.patient).to eq(patient)
    expect(appointment.appointment_slot).to eq(slot)
    expect(appointment.status).to eq("booked")
    expect(appointment.appointment_charges.sole.amount_cents).to eq(6_500)
    expect(appointment.appointment_charges.sole.status).to eq("active")
    expect(AppointmentHold.exists?(hold.id)).to be(false)

    expect(response).to have_http_status(:redirect)
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Booked — Unpaid")
    expect(response.body).to include("payment remains outstanding")
  end

  it "rejects emergency booking if the approved patient link was revoked after reserving" do
    hold = slot.hold_for!(patient: patient)
    senior = create(:staff_member, practice: patient.practice,
      staff_type: "administrator", access_level: "senior_staff_admin")
    Payments::StripeOutageDeclaration.activate!(
      practice: patient.practice, actor: senior, reason: "Stripe outage independently confirmed"
    )

    account.patient_account_links.first.update!(status: "revoked")
    sign_in account, scope: :patient_account
    expect(Stripe::PaymentIntent).not_to receive(:create)

    expect {
      post "/patient-portal/appointment-holds/#{hold.id}/emergency-unpaid"
    }.not_to change(Appointment, :count)
    expect(response).to have_http_status(:forbidden)
    expect(AppointmentCharge.count).to eq(0)
    expect(Payment.count).to eq(0)
    expect(AppointmentHold.exists?(hold.id)).to be(true)
  end

  Payment::STATUSES.each do |payment_status|
    it "blocks emergency unpaid booking when an existing Stripe payment is #{payment_status}" do
      hold = slot.hold_for!(patient: patient)
      senior = create(:staff_member, practice: patient.practice,
        staff_type: "administrator", access_level: "senior_staff_admin")
      Payments::StripeOutageDeclaration.activate!(
        practice: patient.practice, actor: senior, reason: "Stripe outage independently confirmed"
      )
      payment = Payment.create!(
        appointment_hold: hold, patient: patient, provider: "stripe",
        currency: patient.practice.currency, amount_cents: 6_500,
        idempotency_key: SecureRandom.uuid, status: payment_status
      )

      sign_in account, scope: :patient_account
      expect(Stripe::PaymentIntent).not_to receive(:create)

      expect {
        post "/patient-portal/appointment-holds/#{hold.id}/emergency-unpaid"
      }.not_to change(Appointment, :count)
      expect(response).to redirect_to(patient_portal_appointment_hold_path(hold))
      expect(AppointmentCharge.count).to eq(0)
      expect(Payment.count).to eq(1)
      expect(payment.reload.status).to eq(payment_status)
      expect(AppointmentHold.exists?(hold.id)).to be(true)

      get patient_portal_appointment_hold_path(hold)
      expect(response.body).not_to include("Book now — pay later")
    end
  end

  it "rejects emergency unpaid booking after the patient reservation expires" do
    hold = slot.hold_for!(patient: patient)
    senior = create(:staff_member, practice: patient.practice,
      staff_type: "administrator", access_level: "senior_staff_admin")
    Payments::StripeOutageDeclaration.activate!(
      practice: patient.practice, actor: senior, reason: "Stripe outage independently confirmed"
    )
    hold.update!(expires_at: 1.minute.ago)

    sign_in account, scope: :patient_account
    expect(Stripe::PaymentIntent).not_to receive(:create)

    expect {
      post "/patient-portal/appointment-holds/#{hold.id}/emergency-unpaid"
    }.not_to change(Appointment, :count)

    expect(response).to redirect_to(patient_portal_appointment_hold_path(hold))
    expect(AppointmentCharge.count).to eq(0)
    expect(Payment.count).to eq(0)
    expect(AppointmentHold.exists?(hold.id)).to be(true)
  end

  it "does not create another appointment or charge when emergency booking is submitted twice" do
    hold = slot.hold_for!(patient: patient)
    senior = create(:staff_member, practice: patient.practice,
      staff_type: "administrator", access_level: "senior_staff_admin")
    Payments::StripeOutageDeclaration.activate!(
      practice: patient.practice, actor: senior, reason: "Stripe outage independently confirmed"
    )

    sign_in account, scope: :patient_account
    expect(Stripe::PaymentIntent).not_to receive(:create)

    post "/patient-portal/appointment-holds/#{hold.id}/emergency-unpaid"
    expect(response).to have_http_status(:redirect)
    expect(Appointment.count).to eq(1)
    expect(AppointmentCharge.count).to eq(1)

    expect {
      post "/patient-portal/appointment-holds/#{hold.id}/emergency-unpaid"
    }.not_to change(Appointment, :count)
    expect(response).to have_http_status(:not_found)
    expect(AppointmentCharge.count).to eq(1)
    expect(Payment.count).to eq(0)
    expect(AppointmentHold.exists?(hold.id)).to be(false)
  end

end
