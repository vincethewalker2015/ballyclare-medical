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

  it "rejects a blank activation reason without declaring an outage" do
    expect {
      post "/practice/stripe-outage", params: { reason: "   " }
    }.not_to change(AuditEvent, :count)

    expect(response).to redirect_to("/practice/stripe-outage")
    expect(Payments::StripeOutageDeclaration.active?(practice: practice)).to be(false)
  end

  it "rejects a blank deactivation reason and keeps the outage active" do
    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: staff_member, reason: "Stripe incident independently confirmed"
    )

    expect {
      patch "/practice/stripe-outage", params: { reason: "   " }
    }.not_to change(AuditEvent, :count)

    expect(response).to redirect_to("/practice/stripe-outage")
    expect(Payments::StripeOutageDeclaration.active?(practice: practice)).to be(true)
  end

  it "forbids ordinary staff administrators from deactivating an outage" do
    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: staff_member, reason: "Stripe incident independently confirmed"
    )
    staff_member.update!(access_level: "staff_admin")

    expect {
      patch "/practice/stripe-outage", params: { reason: "Claimed restoration" }
    }.not_to change(AuditEvent, :count)

    expect(response).to have_http_status(:forbidden)
    expect(Payments::StripeOutageDeclaration.active?(practice: practice)).to be(true)
  end

  it "does not create a second activation or extend an active outage declaration" do
    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: staff_member, reason: "Stripe incident independently confirmed"
    )
    original_event = AuditEvent.where(practice: practice, action: "stripe_outage.activated").sole

    expect {
      post "/practice/stripe-outage", params: { reason: "Repeat declaration" }
    }.not_to change(AuditEvent, :count)

    expect(response).to redirect_to("/practice/stripe-outage")
    expect(AuditEvent.where(practice: practice, action: "stripe_outage.activated").sole.id).to eq(original_event.id)
    expect(Payments::StripeOutageDeclaration.active?(practice: practice)).to be(true)
  end

  it "shows the declaration form when the outage is inactive and the end control when active" do
    get "/practice/stripe-outage"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Emergency unpaid online booking is inactive")
    expect(response.body).to include("Declare Stripe outage for 30 minutes")
    expect(response.body).not_to include("End Stripe outage now")

    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: staff_member, reason: "Stripe incident independently confirmed"
    )

    get "/practice/stripe-outage"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Emergency unpaid online booking is active")
    expect(response.body).to include("End Stripe outage now")
    expect(response.body).not_to include("Declare Stripe outage for 30 minutes")
  end

  it "forbids non-senior administrators from viewing the outage controls" do
    staff_member.update!(access_level: "staff_admin")

    get "/practice/stripe-outage"

    expect(response).to have_http_status(:forbidden)
  end

  it "shows a Stripe outage navigation link only to senior administrators" do
    get practice_appointments_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('href="/practice/stripe-outage"')

    staff_member.update!(access_level: "staff_admin")
    get practice_appointments_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('href="/practice/stripe-outage"')
  end
end
