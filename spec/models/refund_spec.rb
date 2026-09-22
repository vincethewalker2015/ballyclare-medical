require "rails_helper"

RSpec.describe Refund do
  describe "validations" do
    subject(:refund) { described_class.new }

    let(:payment) { create(:payment) }

    it "is not valid without a currency" do
      refund.assign_attributes(payment: payment, amount_cents: 2500, requested_at: Time.current, status: "pending")
      expect(refund).not_to be_valid
    end

    it "has an error on currency" do
      refund.assign_attributes(payment: payment, amount_cents: 2500, requested_at: Time.current, status: "pending")
      refund.valid?
      expect(refund.errors[:currency]).to be_present
    end

    it "is not valid without a requested_at" do
      refund.assign_attributes(payment: payment, amount_cents: 2500, currency: "GBP", status: "pending")
      expect(refund).not_to be_valid
    end

    it "has an error on requested_at" do
      refund.assign_attributes(payment: payment, amount_cents: 2500, currency: "GBP", status: "pending")
      refund.valid?
      expect(refund.errors[:requested_at]).to be_present
    end

    it "is not valid with a zero amount" do
      refund.assign_attributes(
        payment: payment,
        amount_cents: 0,
        currency: "GBP",
        requested_at: Time.current,
        status: "pending"
      )
      expect(refund).not_to be_valid
    end

    it "has an error on amount_cents for zero" do
      refund.assign_attributes(
        payment: payment,
        amount_cents: 0,
        currency: "GBP",
        requested_at: Time.current,
        status: "pending"
      )
      refund.valid?
      expect(refund.errors[:amount_cents]).to be_present
    end

    it "is not valid with an invalid status" do
      refund.assign_attributes(
        payment: payment,
        amount_cents: 2500,
        currency: "GBP",
        requested_at: Time.current,
        status: "invalid"
      )
      expect(refund).not_to be_valid
    end

    it "has an error on status for an invalid value" do
      refund.assign_attributes(
        payment: payment,
        amount_cents: 2500,
        currency: "GBP",
        requested_at: Time.current,
        status: "invalid"
      )
      refund.valid?
      expect(refund.errors[:status]).to be_present
    end

    it "is valid with required attributes" do
      refund.assign_attributes(
        payment: payment,
        amount_cents: 2500,
        currency: "GBP",
        requested_at: Time.current,
        status: "pending"
      )
      expect(refund).to be_valid
    end
  end
end
