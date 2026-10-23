require "rails_helper"

RSpec.describe "Staff consultation fees", type: :request do
  let(:practice) { create(:practice) }
  let(:user) { create(:user) }

  before do
    create(:staff_member, user: user, practice: practice, access_level: "staff_admin")
    sign_in user
  end

  it "allows a staff administrator to configure doctor and nurse prices" do
    get edit_practice_consultation_fees_path
    expect(response).to have_http_status(:success)

    patch practice_consultation_fees_path, params: {
      consultation_fees: { doctor: "65.00", nurse: "40.00" }
    }

    expect(response).to redirect_to(edit_practice_consultation_fees_path)
    expect(practice.consultation_fees.order(:clinician_type).pluck(:amount_cents)).to eq([ 6500, 4000 ])
    expect(AuditEvent.where(action: "consultation_fee.updated").count).to eq(2)
  end

  it "rejects malformed prices without partially saving the pair" do
    patch practice_consultation_fees_path, params: {
      consultation_fees: { doctor: "65.00", nurse: "-1" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(practice.consultation_fees.count).to eq(0)
  end

  it "prevents ordinary staff from updating fees" do
    user.staff_members.first.update!(access_level: "staff")
    patch practice_consultation_fees_path, params: {
      consultation_fees: { doctor: "65.00", nurse: "40.00" }
    }
    expect(response).to have_http_status(:forbidden)
    expect(practice.consultation_fees.count).to eq(0)
  end
end
