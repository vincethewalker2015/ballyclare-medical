require "rails_helper"

RSpec.describe "Staff refund review", type: :request do
  let(:practice) { create(:practice) }
  let(:user) { create(:user) }
  let!(:membership) do
    create(:staff_member, practice: practice, user: user,
      active: true, access_level: "staff_admin")
  end

  def refund_for(patient:, status:)
    payment = create(:payment,
      patient: patient, appointment: nil, guest_booking: nil,
      status: "requires_refund", provider: "stripe")
    create(:refund, payment: payment, status: status)
  end

  it "requires staff authentication" do
    get practice_refunds_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "shows own-practice refunds including failed exceptions without changing them" do
    own_patient = create(:patient, practice: practice)
    other_patient = create(:patient, practice: create(:practice))
    failed = refund_for(patient: own_patient, status: "failed")
    succeeded = refund_for(patient: own_patient, status: "succeeded")
    foreign = refund_for(patient: other_patient, status: "failed")

    sign_in user
    expect { get practice_refunds_path }.not_to change(Refund, :count)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(failed.id, succeeded.id)
    expect(response.body).not_to include(foreign.id)
    expect(response.body).to include("failed", "succeeded")
    expect(failed.reload.status).to eq("failed")
  end

  it "does not allow basic staff to review refunds" do
    membership.update!(access_level: "staff")
    sign_in user

    get practice_refunds_path

    expect(response).to have_http_status(:forbidden)
  end
end
