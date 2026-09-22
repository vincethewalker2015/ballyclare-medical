require "rails_helper"

RSpec.describe Payment do
  describe "validations" do
    subject(:payment) { described_class.new }

    let(:appointment) { create(:appointment) }
    let(:patient) { appointment.patient }

    it "is not valid without a provider" do
      payment.assign_attributes(appointment: appointment, patient: patient, currency: "GBP", amount_cents: 5000, idempotency_key: "key-1", status: "pending")
      expect(payment).not_to be_valid
    end

    it "has an error on provider" do
      payment.assign_attributes(appointment: appointment, patient: patient, currency: "GBP", amount_cents: 5000, idempotency_key: "key-1", status: "pending")
      payment.valid?
      expect(payment.errors[:provider]).to be_present
    end

    it "is not valid without a currency" do
      payment.assign_attributes(appointment: appointment, patient: patient, provider: "stripe", amount_cents: 5000, idempotency_key: "key-1", status: "pending")
      expect(payment).not_to be_valid
    end

    it "has an error on currency" do
      payment.assign_attributes(appointment: appointment, patient: patient, provider: "stripe", amount_cents: 5000, idempotency_key: "key-1", status: "pending")
      payment.valid?
      expect(payment.errors[:currency]).to be_present
    end

    it "is not valid without an idempotency key" do
      payment.assign_attributes(appointment: appointment, patient: patient, provider: "stripe", currency: "GBP", amount_cents: 5000, status: "pending")
      expect(payment).not_to be_valid
    end

    it "has an error on idempotency_key" do
      payment.assign_attributes(appointment: appointment, patient: patient, provider: "stripe", currency: "GBP", amount_cents: 5000, status: "pending")
      payment.valid?
      expect(payment.errors[:idempotency_key]).to be_present
    end

    it "is not valid with a zero amount" do
      payment.assign_attributes(
        appointment: appointment,
        patient: patient,
        provider: "stripe",
        currency: "GBP",
        amount_cents: 0,
        idempotency_key: "key-1",
        status: "pending"
      )
      expect(payment).not_to be_valid
    end

    it "has an error on amount_cents for zero" do
      payment.assign_attributes(
        appointment: appointment,
        patient: patient,
        provider: "stripe",
        currency: "GBP",
        amount_cents: 0,
        idempotency_key: "key-1",
        status: "pending"
      )
      payment.valid?
      expect(payment.errors[:amount_cents]).to be_present
    end

    it "is not valid with an invalid status" do
      payment.assign_attributes(
        appointment: appointment,
        patient: patient,
        provider: "stripe",
        currency: "GBP",
        amount_cents: 5000,
        idempotency_key: "key-1",
        status: "invalid"
      )
      expect(payment).not_to be_valid
    end

    it "has an error on status for an invalid value" do
      payment.assign_attributes(
        appointment: appointment,
        patient: patient,
        provider: "stripe",
        currency: "GBP",
        amount_cents: 5000,
        idempotency_key: "key-1",
        status: "invalid"
      )
      payment.valid?
      expect(payment.errors[:status]).to be_present
    end

    it "is not valid with a duplicate idempotency key" do
      create(:payment, idempotency_key: "duplicate-key")
      payment.assign_attributes(
        appointment: appointment,
        patient: patient,
        provider: "stripe",
        currency: "GBP",
        amount_cents: 5000,
        idempotency_key: "duplicate-key",
        status: "pending"
      )
      expect(payment).not_to be_valid
    end

    it "has an error on idempotency_key for a duplicate" do
      create(:payment, idempotency_key: "duplicate-key")
      payment.assign_attributes(
        appointment: appointment,
        patient: patient,
        provider: "stripe",
        currency: "GBP",
        amount_cents: 5000,
        idempotency_key: "duplicate-key",
        status: "pending"
      )
      payment.valid?
      expect(payment.errors[:idempotency_key]).to be_present
    end

    it "is valid with required attributes" do
      payment.assign_attributes(
        appointment: appointment,
        patient: patient,
        provider: "stripe",
        currency: "GBP",
        amount_cents: 5000,
        idempotency_key: "key-unique",
        status: "pending"
      )
      expect(payment).to be_valid
    end
  end
end
