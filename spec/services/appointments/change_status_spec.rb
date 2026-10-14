require "rails_helper"

RSpec.describe Appointments::ChangeStatus do
  subject(:change_status) do
    described_class.new(
      appointment: appointment,
      to_status: to_status,
      changed_by: user
    )
  end

  let(:practice) { create(:practice) }
  let(:user) { create(:user) }

  let(:appointment) do
    create(
      :appointment,
      practice: practice,
      status: "booked"
    )
  end

  describe "#call" do
    context "when the transition is allowed" do
      let(:to_status) { "confirmed" }

      it "changes the appointment status" do
        expect {
          change_status.call
        }.to change {
          appointment.reload.status
        }.from("booked").to("confirmed")
      end

      it "records the status change" do
        expect {
          change_status.call
        }.to change(
          AppointmentStatusChange,
          :count
        ).by(1)

        status_change = appointment
          .appointment_status_changes
          .order(:created_at)
          .last

        expect(status_change).to have_attributes(
          from_status: "booked",
          to_status: "confirmed",
          changed_by: user
        )
      end
    end

    context "when the transition is not allowed" do
      let(:to_status) { "completed" }

      it "raises an invalid transition error" do
        expect {
          change_status.call
        }.to raise_error(
          Appointments::ChangeStatus::InvalidTransition
        )
      end

      it "does not change the appointment" do
        expect {
          begin
            change_status.call
          rescue Appointments::ChangeStatus::InvalidTransition
            nil
          end
        }.not_to change {
          appointment.reload.status
        }
      end

      it "does not record a status change" do
        expect {
          begin
            change_status.call
          rescue Appointments::ChangeStatus::InvalidTransition
            nil
          end
        }.not_to change(
          AppointmentStatusChange,
          :count
        )
      end
    end

    context "when cancelling an unpaid appointment" do
      let(:to_status) { "cancelled" }

      let!(:charge) do
        create(
          :appointment_charge,
          appointment: appointment,
          amount_cents: 4000,
          status: "active"
        )
      end

      it "voids the charge and clears the outstanding balance" do
        expect {
          change_status.call
        }.to change {
          charge.reload.status
        }.from("active").to("voided")

        expect(appointment.reload.status).to eq("cancelled")

        balance = Billing::AppointmentBalance.new(
          appointment: appointment
        ).call

        expect(balance[:charged_cents]).to eq(0)
        expect(balance[:balance_cents]).to eq(0)
      end
    end

    context "when cancelling an appointment with a payment in progress" do
      let(:to_status) { "cancelled" }

      let!(:charge) do
        create(
          :appointment_charge,
          appointment: appointment,
          amount_cents: 4000,
          status: "active"
        )
      end

      %w[pending processing].each do |payment_status|
        context "when the payment is #{payment_status}" do
          before do
            create(
              :payment,
              appointment: appointment,
              patient: appointment.patient,
              status: payment_status
            )
          end

          it "rejects cancellation without changing the appointment or charges" do
            expect {
              change_status.call
            }.to raise_error(
              Appointments::ChangeStatus::PaymentInProgress,
              "Cannot cancel an appointment while a payment is in progress."
            )

            expect(appointment.reload.status).to eq("booked")
            expect(charge.reload.status).to eq("active")
            expect(appointment.appointment_status_changes.count).to eq(0)
          end
        end
      end
    end

    context "when staff cancel a paid appointment" do
      let(:to_status) { "cancelled" }

      let!(:charge) do
        create(
          :appointment_charge,
          appointment: appointment,
          amount_cents: 5000,
          status: "active"
        )
      end

      it "voids the consultation charge when cancelling a paid appointment" do
        expect {
          change_status.call
        }.to change {
          charge.reload.status
        }.from("active").to("voided")

        expect(appointment.reload.status).to eq("cancelled")
      end

      let!(:payment) do
        create(
          :payment,
          appointment: appointment,
          patient: appointment.patient,
          status: "succeeded",
          amount_cents: 5000,
          currency: "GBP",
          paid_at: Time.current
        )
      end

      it "creates a pending full refund for the successful payment" do
        expect {
          change_status.call
        }.to change(Refund, :count).by(1)

        refund = payment.refunds.last

        expect(appointment.reload.status).to eq("cancelled")
        expect(refund.amount_cents).to eq(5000)
        expect(refund.currency).to eq("GBP")
        expect(refund.status).to eq("pending")
        expect(refund.requested_by).to eq(user)
        expect(refund.idempotency_key).to be_present
      end

      it "refunds only the remaining amount after a partial refund" do
        create(
          :refund,
          payment: payment,
          amount_cents: 2000,
          currency: "GBP",
          status: "succeeded"
        )

        expect {
          change_status.call
        }.to change(Refund, :count).by(1)

        refund = payment.refunds.order(:created_at).last

        expect(appointment.reload.status).to eq("cancelled")
        expect(refund.amount_cents).to eq(3000)
        expect(refund.status).to eq("pending")
      end

      it "does not create another refund when the payment is fully refunded" do
        create(
          :refund,
          payment: payment,
          amount_cents: 5000,
          currency: "GBP",
          status: "succeeded"
        )

        expect {
          change_status.call
        }.not_to change(Refund, :count)

        expect(appointment.reload.status).to eq("cancelled")
      end

      it "does not duplicate an existing pending refund" do
        create(
          :refund,
          payment: payment,
          amount_cents: 2000,
          currency: "GBP",
          status: "pending"
        )

        expect {
          change_status.call
        }.to change(Refund, :count).by(1)

        new_refund = payment.refunds.order(:created_at).last

        expect(appointment.reload.status).to eq("cancelled")
        expect(new_refund.amount_cents).to eq(3000)
        expect(new_refund.status).to eq("pending")
      end

      it "enqueues processing for the newly created refund" do
        expect(ProcessRefundJob).to receive(:perform_later) do |refund_id|
          refund = payment.refunds.find(refund_id)

          expect(refund.status).to eq("pending")
          expect(refund.amount_cents).to eq(5000)
        end

        change_status.call

        expect(appointment.reload.status).to eq("cancelled")
      end

      it "does not enqueue a refund job when cancellation rolls back" do
        allow_any_instance_of(AppointmentStatusChange)
          .to receive(:save!)
          .and_raise(ActiveRecord::RecordInvalid)

        expect(ProcessRefundJob).not_to receive(:perform_later)

        expect {
          change_status.call
        }.to raise_error(ActiveRecord::RecordInvalid)

        expect(appointment.reload.status).to eq("booked")
        expect(payment.refunds.count).to eq(0)
      end

      it "keeps cancellation successful when refund job enqueueing fails" do
        allow(ProcessRefundJob)
          .to receive(:perform_later)
          .and_raise(StandardError, "Queue unavailable")

        expect {
          change_status.call
        }.not_to raise_error

        expect(appointment.reload.status).to eq("cancelled")

        refund = payment.refunds.last

        expect(refund).to be_present
        expect(refund.status).to eq("pending")
        expect(refund.amount_cents).to eq(5000)
      end
    end
  end
end
