require "rails_helper"
require "active_support/testing/time_helpers"


RSpec.describe Payments::StripeOutageDeclaration do
  include ActiveSupport::Testing::TimeHelpers
  let(:practice) { create(:practice) }
  let(:administrator) do
    create(:staff_member, practice: practice, staff_type: "administrator",
      access_level: "senior_staff_admin")
  end

  it "defaults to inactive without an authorized declaration" do
    expect(described_class.active?(practice: practice)).to be(false)
  end

  it "records a time-limited, auditable declaration by a senior administrator" do
    travel_to Time.zone.parse("2026-10-28 12:00:00") do
      expect {
        described_class.activate!(practice: practice, actor: administrator,
          reason: "Stripe status page confirms a service outage")
      }.to change(AuditEvent, :count).by(1)

      event = AuditEvent.last
      expect(event.practice).to eq(practice)
      expect(event.user).to eq(administrator.user)
      expect(event.action).to eq("stripe_outage.activated")
      expect(event.metadata["reason"]).to eq("Stripe status page confirms a service outage")
      expect(described_class.active?(practice: practice)).to be(true)

      travel 31.minutes
      expect(described_class.active?(practice: practice)).to be(false)
    end
  end

  it "rejects activation by a non-senior staff member" do
    ordinary_staff = create(:staff_member, practice: practice,
      staff_type: "administrator", access_level: "staff_admin")

    expect {
      described_class.activate!(practice: practice, actor: ordinary_staff,
        reason: "Outage confirmed")
    }.to raise_error(Payments::StripeOutageDeclaration::Unauthorized)

    expect(described_class.active?(practice: practice)).to be(false)
  end

  it "does not allow an administrator from another practice to activate the outage" do
    other_practice = create(:practice)

    expect {
      described_class.activate!(practice: other_practice, actor: administrator,
        reason: "Outage confirmed")
    }.to raise_error(Payments::StripeOutageDeclaration::Unauthorized)
  end

  it "allows a senior administrator to deactivate an active declaration" do
    described_class.activate!(practice: practice, actor: administrator,
      reason: "Outage confirmed")
    described_class.deactivate!(practice: practice, actor: administrator,
      reason: "Stripe service restored")

    expect(described_class.active?(practice: practice)).to be(false)
    expect(AuditEvent.order(:created_at).last.action).to eq("stripe_outage.deactivated")
  end

  it "keeps declarations isolated between practices" do
    described_class.activate!(practice: practice, actor: administrator,
      reason: "Outage confirmed")

    expect(described_class.active?(practice: create(:practice))).to be(false)
  end
end
