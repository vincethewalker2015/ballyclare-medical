require "rails_helper"

RSpec.describe Billing::AppointmentBalances do
  describe "#call" do
    let(:appointment) { create(:appointment) }

    let(:other_appointment) do
      create(
        :appointment,
        practice: appointment.practice
      )
    end

    subject(:balances) do
      described_class.new(
        appointments: [ appointment, other_appointment ]
      ).call
    end

    it "returns zero totals when there is no financial activity" do
      expect(balances.fetch(appointment.id)).to eq(
        charged_cents: 0,
        paid_cents: 0,
        refunded_cents: 0,
        balance_cents: 0,
        currency: appointment.practice.currency
      )

      expect(balances.fetch(other_appointment.id)).to eq(
        charged_cents: 0,
        paid_cents: 0,
        refunded_cents: 0,
        balance_cents: 0,
        currency: appointment.practice.currency
      )
    end

    it "calculates an unpaid balance" do
      create(
        :appointment_charge,
        appointment: appointment,
        patient: appointment.patient,
        practice: appointment.practice,
        amount_cents: 5000,
        status: "active"
      )

      expect(balances.fetch(appointment.id)).to eq(
        charged_cents: 5000,
        paid_cents: 0,
        refunded_cents: 0,
        balance_cents: 5000,
        currency: appointment.practice.currency
      )
    end

    it "calculates a partially paid balance" do
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

      expect(balances.fetch(appointment.id)).to eq(
        charged_cents: 5000,
        paid_cents: 2000,
        refunded_cents: 0,
        balance_cents: 3000,
        currency: appointment.practice.currency
      )
    end

    it "calculates a fully paid balance" do
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
        status: "succeeded"
      )

      expect(balances.fetch(appointment.id)).to eq(
        charged_cents: 5000,
        paid_cents: 5000,
        refunded_cents: 0,
        balance_cents: 0,
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

      expect(balances.fetch(appointment.id)).to eq(
        charged_cents: 5000,
        paid_cents: 5000,
        refunded_cents: 2000,
        balance_cents: 2000,
        currency: appointment.practice.currency
      )
    end

    it "preserves a negative balance for an overpaid appointment" do
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

      expect(balances.fetch(appointment.id)).to eq(
        charged_cents: 5000,
        paid_cents: 6000,
        refunded_cents: 0,
        balance_cents: -1000,
        currency: appointment.practice.currency
      )
    end

    it "keeps financial activity separated between appointments" do
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
        appointment: other_appointment,
        patient: other_appointment.patient,
        practice: other_appointment.practice,
        amount_cents: 8000,
        status: "active"
      )

      create(
        :payment,
        appointment: other_appointment,
        appointment_hold: nil,
        patient: other_appointment.patient,
        amount_cents: 3000,
        currency: other_appointment.practice.currency,
        status: "succeeded"
      )

      expect(
        balances.fetch(appointment.id)[:balance_cents]
      ).to eq(5000)

      expect(
        balances.fetch(other_appointment.id)[:balance_cents]
      ).to eq(5000)

      expect(
        balances.fetch(appointment.id)[:paid_cents]
      ).to eq(0)

      expect(
        balances.fetch(other_appointment.id)[:paid_cents]
      ).to eq(3000)
    end

    it "ignores voided charges and unsuccessful payments and refunds" do
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
        amount_cents: 2000,
        status: "voided"
      )

      %w[pending processing failed cancelled requires_refund].each do |status|
        create(
          :payment,
          appointment: appointment,
          appointment_hold: nil,
          patient: appointment.patient,
          amount_cents: 500,
          currency: appointment.practice.currency,
          status: status
        )
      end

      successful_payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        amount_cents: 1000,
        currency: appointment.practice.currency,
        status: "succeeded"
      )

      %w[pending processing failed cancelled].each do |status|
        create(
          :refund,
          payment: successful_payment,
          amount_cents: 100,
          currency: successful_payment.currency,
          status: status
        )
      end

      expect(balances.fetch(appointment.id)).to eq(
        charged_cents: 5000,
        paid_cents: 1000,
        refunded_cents: 0,
        balance_cents: 4000,
        currency: appointment.practice.currency
      )
    end
  end
end
