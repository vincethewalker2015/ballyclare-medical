require "rails_helper"

RSpec.describe Payments::CreateForAppointment do
  describe "#call" do
    let(:appointment) { create(:appointment) }

    before do
      create(
        :appointment_charge,
        appointment: appointment,
        patient: appointment.patient,
        practice: appointment.practice,
        amount_cents: 5000,
        status: "active"
      )
    end

    subject(:call_service) do
      described_class.new(
        appointment: appointment,
        amount_cents: 5000
      ).call
    end

    it "creates a pending payment for the appointment" do
      expect { call_service }
        .to change(Payment, :count)
        .by(1)

      payment = Payment.last

      expect(payment).to have_attributes(
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        amount_cents: 5000,
        currency: appointment.practice.currency,
        provider: "stripe",
        status: "pending"
      )

      expect(payment.idempotency_key).to be_present
    end

    it "allows a partial payment against the outstanding balance" do
      service = described_class.new(
        appointment: appointment,
        amount_cents: 2000
      )

      payment = service.call

      expect(payment.amount_cents).to eq(2000)
      expect(payment.status).to eq("pending")
    end

    it "rejects a payment greater than the outstanding balance" do
      service = described_class.new(
        appointment: appointment,
        amount_cents: 6000
      )

      expect { service.call }
        .to raise_error(
          Payments::CreateForAppointment::AmountExceedsBalance
        )

      expect(Payment.count).to eq(0)
    end
    it "rejects a new payment while another payment is pending" do
      create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        amount_cents: 5000,
        currency: appointment.practice.currency,
        status: "pending"
      )

      expect { call_service }
        .to raise_error(
          Payments::CreateForAppointment::PaymentInProgress
        )

      expect(
        appointment.payments.where(status: "pending").count
      ).to eq(1)
    end
    it "rejects a new payment while another payment is processing" do
      create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        amount_cents: 5000,
        currency: appointment.practice.currency,
        status: "processing"
      )

      expect { call_service }
        .to raise_error(
          Payments::CreateForAppointment::PaymentInProgress
        )

      expect(
        appointment.payments.where(status: "processing").count
      ).to eq(1)
    end
    it "allows a new payment after a failed payment" do
  create(
    :payment,
    appointment: appointment,
    appointment_hold: nil,
    patient: appointment.patient,
    amount_cents: 5000,
    currency: appointment.practice.currency,
    status: "failed"
  )

  expect { call_service }
    .to change(Payment, :count)
    .by(1)

  expect(Payment.order(:created_at).last.status)
    .to eq("pending")
end

    it "allows a new payment after a cancelled payment" do
      create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        amount_cents: 5000,
        currency: appointment.practice.currency,
        status: "cancelled"
      )

      expect { call_service }
        .to change(Payment, :count)
        .by(1)

      expect(Payment.order(:created_at).last.status)
        .to eq("pending")
    end

    context "when the appointment is cancelled" do
      before do
        appointment.update!(status: "cancelled")
      end

      it "rejects the payment without creating a record" do
        expect do
          expect { call_service }
            .to raise_error(
              Payments::CreateForAppointment::AppointmentCancelled,
              "Cannot take payment for a cancelled appointment."
            )
        end.not_to change(Payment, :count)
      end
    end
    it "rejects a zero payment amount" do
      service = described_class.new(
        appointment: appointment,
        amount_cents: 0
      )

      expect { service.call }
        .to raise_error(ActiveRecord::RecordInvalid)

      expect(Payment.count).to eq(0)
    end

    it "rejects a negative payment amount" do
      service = described_class.new(
        appointment: appointment,
        amount_cents: -100
      )

      expect { service.call }
        .to raise_error(ActiveRecord::RecordInvalid)

      expect(Payment.count).to eq(0)
    end
  end
end
