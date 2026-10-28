require "rails_helper"
require "active_support/testing/time_helpers"

RSpec.describe Payments::EmergencyUnpaidBookingPolicy do
  include ActiveSupport::Testing::TimeHelpers
  let(:practice) { create(:practice) }
  let(:administrator) do
    create(:staff_member, practice: practice, staff_type: "administrator",
      access_level: "senior_staff_admin")
  end

  def declare_outage
    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: administrator, reason: "Stripe outage independently confirmed"
    )
  end

  it "defaults to disabled when the practice has no outage declaration" do
    expect(described_class.new(practice: practice, payment: nil).allowed?).to be(false)
  end

  it "allows unpaid booking when the practice has an active declaration and no payment attempt" do
    declare_outage
    expect(described_class.new(practice: practice, payment: nil).allowed?).to be(true)
  end

  it "rejects a deactivated declaration" do
    declare_outage
    Payments::StripeOutageDeclaration.deactivate!(
      practice: practice, actor: administrator, reason: "Stripe recovered"
    )
    expect(described_class.new(practice: practice, payment: nil).allowed?).to be(false)
  end

  it "rejects an expired declaration" do
    travel_to Time.zone.parse("2026-10-28 12:00:00") do
      declare_outage
      travel 31.minutes
      expect(described_class.new(practice: practice, payment: nil).allowed?).to be(false)
    end
  end

  it "does not accept another practice's declaration" do
    declare_outage
    expect(described_class.new(practice: create(:practice), payment: nil).allowed?).to be(false)
  end

  %w[pending processing succeeded failed cancelled requires_refund].each do |status|
    it "rejects a #{status} payment even with an active declaration" do
      declare_outage
      payment = instance_double(Payment, status: status)
      expect(described_class.new(practice: practice, payment: payment).allowed?).to be(false)
    end
  end
end
