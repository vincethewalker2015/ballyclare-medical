require "rails_helper"

RSpec.describe Billing::CreateCharge do
  describe "#call" do
    let(:appointment) { create(:appointment) }
    let(:created_by) { create(:user) }

    subject(:call_service) do
      described_class.new(
        appointment: appointment,
        description: "Blood test",
        charge_type: "additional",
        amount_cents: 3500,
        created_by: created_by
      ).call
    end

    it "creates an appointment charge" do
      expect { call_service }
        .to change(AppointmentCharge, :count)
        .by(1)
    end

    it "records the supplied charge details" do
      charge = call_service

      expect(charge).to have_attributes(
        appointment: appointment,
        description: "Blood test",
        charge_type: "additional",
        amount_cents: 3500,
        created_by: created_by,
        status: "active"
      )
    end

    it "derives the patient from the appointment" do
      charge = call_service

      expect(charge.patient).to eq(appointment.patient)
    end

    it "derives the practice from the appointment" do
      charge = call_service

      expect(charge.practice).to eq(appointment.practice)
    end

    it "derives the currency from the appointment practice" do
      charge = call_service

      expect(charge.currency).to eq(appointment.practice.currency)
    end

    it "records when the charge was created" do
      charge = call_service

      expect(charge.charged_at).to be_present
    end

    it "uses the appointment practice currency" do
      appointment.practice.update!(currency: "EUR")

      charge = call_service

      expect(charge.currency).to eq("EUR")
    end

    context "with invalid charge details" do
      it "rejects a zero amount" do
        service = described_class.new(
          appointment: appointment,
          description: "Blood test",
          charge_type: "additional",
          amount_cents: 0,
          created_by: created_by
        )

        expect { service.call }
          .to raise_error(ActiveRecord::RecordInvalid)

        expect(AppointmentCharge.count).to eq(0)
      end

      it "rejects a negative amount" do
        service = described_class.new(
          appointment: appointment,
          description: "Blood test",
          charge_type: "additional",
          amount_cents: -100,
          created_by: created_by
        )

        expect { service.call }
          .to raise_error(ActiveRecord::RecordInvalid)

        expect(AppointmentCharge.count).to eq(0)
      end

      it "rejects a blank description" do
        service = described_class.new(
          appointment: appointment,
          description: "",
          charge_type: "additional",
          amount_cents: 3500,
          created_by: created_by
        )

        expect { service.call }
          .to raise_error(ActiveRecord::RecordInvalid)

        expect(AppointmentCharge.count).to eq(0)
      end

      it "rejects an invalid charge type" do
        service = described_class.new(
          appointment: appointment,
          description: "Blood test",
          charge_type: "invalid",
          amount_cents: 3500,
          created_by: created_by
        )

        expect { service.call }
          .to raise_error(ActiveRecord::RecordInvalid)

        expect(AppointmentCharge.count).to eq(0)
      end
    end

    context "when the appointment is cancelled" do
      before do
        appointment.update!(status: "cancelled")
      end

      it "rejects the charge without creating a record" do
        expect do
          expect { call_service }
            .to raise_error(
              Billing::CreateCharge::AppointmentCancelled,
              "Cannot add charges to a cancelled appointment."
            )
        end.not_to change(AppointmentCharge, :count)
      end
    end
  end
end
