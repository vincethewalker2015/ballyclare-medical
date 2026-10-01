require "rails_helper"

RSpec.describe Appointment, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:appointment_charges) }

    it "restricts destruction when appointment charges exist" do
      association = described_class.reflect_on_association(
        :appointment_charges
      )

      expect(association.options[:dependent])
        .to eq(:restrict_with_error)
    end
  end

  describe "validations" do
    subject(:appointment) { described_class.new }

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

    it "is not valid without a status" do
      appointment.assign_attributes(
        practice: practice,
        clinician: clinician,
        patient: patient,
        appointment_slot: appointment_slot,
        booked_at: Time.current,
        status: nil
      )

      expect(appointment).not_to be_valid
    end

    it "has an error on status" do
      appointment.assign_attributes(
        practice: practice,
        clinician: clinician,
        patient: patient,
        appointment_slot: appointment_slot,
        booked_at: Time.current,
        status: nil
      )

      appointment.valid?

      expect(appointment.errors[:status]).to be_present
    end

    it "is not valid with an invalid status" do
      appointment.assign_attributes(
        practice: practice,
        clinician: clinician,
        patient: patient,
        appointment_slot: appointment_slot,
        booked_at: Time.current,
        status: "invalid"
      )

      expect(appointment).not_to be_valid
    end

    it "has an error on status for an invalid value" do
      appointment.assign_attributes(
        practice: practice,
        clinician: clinician,
        patient: patient,
        appointment_slot: appointment_slot,
        booked_at: Time.current,
        status: "invalid"
      )

      appointment.valid?

      expect(appointment.errors[:status]).to be_present
    end

    it "is not valid without a booked_at" do
      appointment.assign_attributes(
        practice: practice,
        clinician: clinician,
        patient: patient,
        appointment_slot: appointment_slot,
        status: "booked",
        booked_at: nil
      )

      expect(appointment).not_to be_valid
    end

    it "has an error on booked_at" do
      appointment.assign_attributes(
        practice: practice,
        clinician: clinician,
        patient: patient,
        appointment_slot: appointment_slot,
        status: "booked",
        booked_at: nil
      )

      appointment.valid?

      expect(appointment.errors[:booked_at]).to be_present
    end

    it "is valid with required attributes" do
      appointment.assign_attributes(
        practice: practice,
        clinician: clinician,
        patient: patient,
        appointment_slot: appointment_slot,
        status: "booked",
        booked_at: Time.current
      )

      expect(appointment).to be_valid
    end
  end
end
