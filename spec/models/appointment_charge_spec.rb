require "rails_helper"

RSpec.describe AppointmentCharge, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:appointment) }
    it { is_expected.to belong_to(:patient) }
    it { is_expected.to belong_to(:practice) }

    it do
      is_expected.to belong_to(:created_by)
        .class_name("User")
        .optional
    end
  end

  describe "validations" do
    subject(:appointment_charge) { build(:appointment_charge) }

    it { is_expected.to validate_presence_of(:description) }
    it { is_expected.to validate_presence_of(:currency) }
    it { is_expected.to validate_presence_of(:charged_at) }

    it do
      is_expected.to validate_numericality_of(:amount_cents)
        .only_integer
        .is_greater_than(0)
    end

    it do
      is_expected.to validate_inclusion_of(:status)
        .in_array(described_class::STATUSES)
    end

    it do
      is_expected.to validate_inclusion_of(:charge_type)
        .in_array(described_class::CHARGE_TYPES)
    end
  end

  describe "appointment relationship consistency" do
    let(:appointment) { create(:appointment) }

    it "is valid when the patient and practice match the appointment" do
      charge = build(
        :appointment_charge,
        appointment: appointment,
        patient: appointment.patient,
        practice: appointment.practice
      )

      expect(charge).to be_valid
    end

    it "is invalid when the patient does not match the appointment" do
      other_patient = create(
        :patient,
        practice: appointment.practice
      )

      charge = build(
        :appointment_charge,
        appointment: appointment,
        patient: other_patient,
        practice: appointment.practice
      )

      expect(charge).not_to be_valid
      expect(charge.errors[:patient]).to include(
        "must match the appointment patient"
      )
    end

    it "is invalid when the practice does not match the appointment" do
      other_practice = create(:practice)
      other_patient = create(
        :patient,
        practice: other_practice
      )

      charge = build(
        :appointment_charge,
        appointment: appointment,
        patient: other_patient,
        practice: other_practice
      )

      expect(charge).not_to be_valid
      expect(charge.errors[:practice]).to include(
        "must match the appointment practice"
      )
    end
  end

  describe ".active" do
    it "returns active charges and excludes voided charges" do
      active_charge = create(:appointment_charge)

      voided_charge = create(
        :appointment_charge,
        status: "voided"
      )

      expect(described_class.active).to include(active_charge)
      expect(described_class.active).not_to include(voided_charge)
    end
  end
end
