require "rails_helper"

RSpec.describe Billing::AppointmentBalance do
  describe "#call" do
    let(:appointment) { create(:appointment) }

    subject(:balance) do
      described_class.new(
        appointment: appointment
      ).call
    end

    it "returns zero totals when there is no financial activity" do
      expect(balance).to eq(
        charged_cents: 0,
        paid_cents: 0,
        refunded_cents: 0,
        balance_cents: 0,
        currency: appointment.practice.currency
      )
    end
    it "includes active appointment charges in the charged total and balance" do
      create(
        :appointment_charge,
        appointment: appointment,
        patient: appointment.patient,
        practice: appointment.practice,
        amount_cents: 5000,
        status: "active"
      )

      create(
        :appointment_charge,
        appointment: appointment,
        patient: appointment.patient,
        practice: appointment.practice,
        amount_cents: 2500,
        status: "active"
      )

      expect(balance).to eq(
        charged_cents: 7500,
        paid_cents: 0,
        refunded_cents: 0,
        balance_cents: 7500,
        currency: appointment.practice.currency
      )
    end
    it "excludes voided charges from the charged total and balance" do
      create(
        :appointment_charge,
        appointment: appointment,
        patient: appointment.patient,
        practice: appointment.practice,
        amount_cents: 5000,
        status: "active"
      )

      create(
        :appointment_charge,
        appointment: appointment,
        patient: appointment.patient,
        practice: appointment.practice,
        amount_cents: 2500,
        status: "voided"
      )

      expect(balance).to eq(
        charged_cents: 5000,
        paid_cents: 0,
        refunded_cents: 0,
        balance_cents: 5000,
        currency: appointment.practice.currency
      )
    end
    it "subtracts successful payments from the outstanding balance" do
      create(
        :appointment_charge,
        appointment: appointment,
        patient: appointment.patient,
        practice: appointment.practice,
        amount_cents: 5000,
        status: "active"
      )

      create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        amount_cents: 2000,
        currency: appointment.practice.currency,
        status: "succeeded"
      )

      expect(balance).to eq(
        charged_cents: 5000,
        paid_cents: 2000,
        refunded_cents: 0,
        balance_cents: 3000,
        currency: appointment.practice.currency
      )
    end
    it "excludes unsuccessful payments from the paid total and balance" do
      create(
        :appointment_charge,
        appointment: appointment,
        patient: appointment.patient,
        practice: appointment.practice,
        amount_cents: 5000,
        status: "active"
      )

      %w[pending processing failed cancelled].each do |status|
        create(
          :payment,
          appointment: appointment,
          appointment_hold: nil,
          patient: appointment.patient,
          amount_cents: 1000,
          currency: appointment.practice.currency,
          status: status
        )
      end

      expect(balance).to eq(
        charged_cents: 5000,
        paid_cents: 0,
        refunded_cents: 0,
        balance_cents: 5000,
        currency: appointment.practice.currency
      )
    end
    it "adds successful refunds back to the outstanding balance" do
      create(
        :appointment_charge,
        appointment: appointment,
        patient: appointment.patient,
        practice: appointment.practice,
        amount_cents: 5000,
        status: "active"
      )

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        amount_cents: 5000,
        currency: appointment.practice.currency,
        status: "succeeded"
      )

      create(
        :refund,
        payment: payment,
        amount_cents: 2000,
        currency: payment.currency,
        status: "succeeded"
      )

      expect(balance).to eq(
        charged_cents: 5000,
        paid_cents: 5000,
        refunded_cents: 2000,
        balance_cents: 2000,
        currency: appointment.practice.currency
      )
    end
    it "excludes unsuccessful refunds from the refunded total and balance" do
      create(
        :appointment_charge,
        appointment: appointment,
        patient: appointment.patient,
        practice: appointment.practice,
        amount_cents: 5000,
        status: "active"
      )

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        amount_cents: 5000,
        currency: appointment.practice.currency,
        status: "succeeded"
      )

      %w[pending processing failed cancelled].each do |status|
        create(
          :refund,
          payment: payment,
          amount_cents: 500,
          currency: payment.currency,
          status: status
        )
      end

      expect(balance).to eq(
        charged_cents: 5000,
        paid_cents: 5000,
        refunded_cents: 0,
        balance_cents: 0,
        currency: appointment.practice.currency
      )
    end
    it "does not count payments requiring a refund as paid" do
      create(
        :appointment_charge,
        appointment: appointment,
        patient: appointment.patient,
        practice: appointment.practice,
        amount_cents: 5000,
        status: "active"
      )

      create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        amount_cents: 5000,
        currency: appointment.practice.currency,
        status: "requires_refund"
      )

      expect(balance).to eq(
        charged_cents: 5000,
        paid_cents: 0,
        refunded_cents: 0,
        balance_cents: 5000,
        currency: appointment.practice.currency
      )
    end
    it "returns a negative balance when the appointment is overpaid" do
      create(
        :appointment_charge,
        appointment: appointment,
        patient: appointment.patient,
        practice: appointment.practice,
        amount_cents: 5000,
        status: "active"
      )

      create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        amount_cents: 6000,
        currency: appointment.practice.currency,
        status: "succeeded"
      )

      expect(balance).to eq(
        charged_cents: 5000,
        paid_cents: 6000,
        refunded_cents: 0,
        balance_cents: -1000,
        currency: appointment.practice.currency
      )
    end
  end
end
