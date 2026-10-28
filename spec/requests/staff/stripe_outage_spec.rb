require "rails_helper"

RSpec.describe "Senior staff Stripe outage controls", type: :request do
  let(:practice) { create(:practice) }
  let(:user) { create(:user) }
  let!(:staff_member) do
    create(:staff_member, user: user, practice: practice,
      staff_type: "administrator", access_level: "senior_staff_admin")
  end

  before { sign_in user }

  it "lets a senior administrator declare an outage with a reason and an audit record" do
    expect {
      post "/practice/stripe-outage", params: {
        reason: "Stripe incident independently confirmed"
      }
    }.to change {
      AuditEvent.where(practice: practice, action: "stripe_outage.activated").count
    }.by(1)

    expect(response).to redirect_to("/practice/stripe-outage")
    expect(Payments::StripeOutageDeclaration.active?(practice: practice)).to be(true)
    event = AuditEvent.where(practice: practice, action: "stripe_outage.activated").sole
    expect(event.user).to eq(user)
    expect(event.metadata.fetch("reason")).to eq("Stripe incident independently confirmed")
  end

  it "forbids ordinary staff administrators from declaring an outage" do
    staff_member.update!(access_level: "staff_admin")

    expect {
      post "/practice/stripe-outage", params: { reason: "Claimed outage" }
    }.not_to change(AuditEvent, :count)

    expect(response).to have_http_status(:forbidden)
    expect(Payments::StripeOutageDeclaration.active?(practice: practice)).to be(false)
  end
  it "lets a senior administrator deactivate an outage with an audit reason" do
    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: staff_member, reason: "Stripe incident independently confirmed"
    )

    expect {
      patch "/practice/stripe-outage", params: {
        reason: "Stripe service restored and verified"
      }
    }.to change {
      AuditEvent.where(practice: practice, action: "stripe_outage.deactivated").count
    }.by(1)

    expect(response).to redirect_to("/practice/stripe-outage")
    expect(Payments::StripeOutageDeclaration.active?(practice: practice)).to be(false)
    event = AuditEvent.where(practice: practice, action: "stripe_outage.deactivated").sole
    expect(event.user).to eq(user)
    expect(event.metadata.fetch("reason")).to eq("Stripe service restored and verified")
  end

end
