require "rails_helper"

RSpec.describe Payments::EmergencyUnpaidBookingPolicy do
  describe "#allowed?" do
    it "defaults to disabled when no operator-confirmed outage is active" do
      policy = described_class.new(outage_confirmed: false, payment: nil)
      expect(policy.allowed?).to be(false)
    end

    it "allows emergency unpaid booking only with an explicit confirmed outage and no payment attempt" do
      policy = described_class.new(outage_confirmed: true, payment: nil)
      expect(policy.allowed?).to be(true)
    end

    %w[pending processing succeeded failed cancelled requires_refund].each do |status|
      it "refuses fallback when a #{status} payment already exists" do
        payment = instance_double(Payment, status: status)
        policy = described_class.new(outage_confirmed: true, payment: payment)
        expect(policy.allowed?).to be(false)
      end
    end

    it "refuses fallback when the outage is not confirmed even if Stripe reports a timeout" do
      policy = described_class.new(outage_confirmed: false, payment: nil)
      expect(policy.allowed?).to be(false)
    end
  end
end
