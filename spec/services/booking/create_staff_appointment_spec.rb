require "rails_helper"

RSpec.describe Booking::CreateStaffAppointment do
  describe "#call" do
    let(:practice) { create(:practice) }
    let(:clinician) do
      create(:staff_member, practice: practice)
    end
    let(:patient) do
      create(:patient, practice: practice)
    end
    let(:appointment_slot) do
      create(
        :appointment_slot,
        practice: practice,
        clinician: clinician
      )
    end
    let(:booked_by) { create(:user) }

    subject(:call_service) do
      described_class.new(
        appointment_slot: appointment_slot,
        patient: patient,
        booked_by: booked_by,
        reason: "Routine consultation",
        amount_cents: 5000
      ).call
    end

    it "creates an appointment without requiring payment" do
      expect { call_service }
        .to change(Appointment, :count)
        .by(1)
    end
    it "does not book an appointment slot that is already booked" do
      create(
        :appointment,
        practice: appointment_slot.practice,
        appointment_slot: appointment_slot,
        patient: patient,
        clinician: appointment_slot.clinician
      )

      expect { call_service }
        .to raise_error(Booking::CreateStaffAppointment::SlotUnavailable)

      expect(Appointment.where(appointment_slot: appointment_slot).count)
        .to eq(1)
    end
    it "does not book a slot with an active patient hold" do
      create(
        :appointment_hold,
        appointment_slot: appointment_slot,
        patient: patient,
        expires_at: 5.minutes.from_now
      )

      expect { call_service }
        .to raise_error(Booking::CreateStaffAppointment::SlotUnavailable)

      expect(
        Appointment.where(appointment_slot: appointment_slot)
      ).to be_empty
    end
    it "allows booking when the existing hold has expired" do
      create(
        :appointment_hold,
        appointment_slot: appointment_slot,
        patient: patient,
        expires_at: 5.minutes.ago
      )

      expect { call_service }
        .to change(Appointment, :count)
        .by(1)

      appointment = Appointment.find_by!(
        appointment_slot: appointment_slot
      )

      expect(appointment.patient).to eq(patient)
    end
    it "does not book a patient from another practice" do
      other_practice = create(:practice)
      other_patient = create(
        :patient,
        practice: other_practice
      )

      service = described_class.new(
        appointment_slot: appointment_slot,
        patient: other_patient,
        booked_by: booked_by,
        reason: "Routine consultation",
        amount_cents: 5000
      )

      expect { service.call }
        .to raise_error(
          Booking::CreateStaffAppointment::PracticeMismatch
        )

      expect(Appointment.count).to eq(0)
    end
    it "creates an initial appointment charge without requiring payment" do
      appointment = call_service

      expect(appointment.appointment_charges.count).to eq(1)

      charge = appointment.appointment_charges.first

      expect(charge).to have_attributes(
        patient: patient,
        practice: practice,
        created_by: booked_by,
        description: "Routine consultation",
        charge_type: "appointment",
        amount_cents: 5000,
        currency: practice.currency,
        status: "active"
      )

      expect(appointment.payments).to be_empty
    end
    it "rolls back the appointment when the initial charge cannot be created" do
      service = described_class.new(
        appointment_slot: appointment_slot,
        patient: patient,
        booked_by: booked_by,
        reason: "Routine consultation",
        amount_cents: 0
      )

      expect { service.call }
        .to raise_error(ActiveRecord::RecordInvalid)

      expect(
        Appointment.where(appointment_slot: appointment_slot)
      ).to be_empty

      expect(AppointmentCharge.count).to eq(0)
    end
    it "leaves the appointment balance outstanding when no payment is taken" do
      appointment = call_service

      balance = Billing::AppointmentBalance.new(
        appointment: appointment
      ).call

      expect(balance).to eq(
        charged_cents: 5000,
        paid_cents: 0,
        refunded_cents: 0,
        balance_cents: 5000,
        currency: practice.currency
      )
    end
  end
end
