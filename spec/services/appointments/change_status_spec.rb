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
  end
end
