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
end
