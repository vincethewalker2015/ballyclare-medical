require "rails_helper"

RSpec.describe "Staff unresolved booking payment review", type: :request do
  let(:practice) { create(:practice) }
  let(:user) { create(:user) }

  before do
    create(:staff_member, practice: practice, user: user,
      active: true, access_level: "staff_admin")
  end

  it "lists stale unresolved booking payments without Stripe IDs only for the staff member's practice" do
    own_patient = create(:patient, practice: practice)
    other_patient = create(:patient, practice: create(:practice))
    own_payment = create(:payment, appointment: nil, patient: own_patient,
      status: "pending", provider_payment_id: nil)
    foreign_payment = create(:payment, appointment: nil, patient: other_patient,
      status: "pending", provider_payment_id: nil)
    own_payment.update_columns(updated_at: 20.minutes.ago)
    foreign_payment.update_columns(updated_at: 20.minutes.ago)

    sign_in user

    expect {
      get practice_booking_payment_reconciliations_path
    }.not_to change(Payment, :count)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_payment.id.to_s)
    expect(response.body).not_to include(foreign_payment.id.to_s)
    expect(own_payment.reload.status).to eq("pending")
    expect(own_payment.provider_payment_id).to be_nil
  end
end
