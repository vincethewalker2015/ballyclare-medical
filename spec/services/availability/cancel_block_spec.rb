require "rails_helper"

RSpec.describe Availability::CancelBlock do
  let(:practice) do
    Practice.create!(
      name: "Test Medical Centre",
      timezone: "Europe/London",
      currency: "GBP",
      country_code: "GB"
    )
  end

  let(:clinician_user) do
    User.create!(
      email: "doctor@example.com",
      password: "password123"
    )
  end

  let(:clinician) do
    StaffMember.create!(
      practice: practice,
      user: clinician_user,
      staff_type: "doctor",
      default_appointment_duration: 30
    )
  end

  let(:availability_block) do
    AvailabilityBlock.create!(
      practice: practice,
      clinician: clinician,
      starts_at: 1.day.from_now.change(hour: 9),
      ends_at: 1.day.from_now.change(hour: 10),
      slot_duration_minutes: 30,
      bookable_online: true
    )
  end

  describe "#call" do
    it "cancels the availability block" do
      described_class.new(
        availability_block: availability_block
      ).call

      expect(availability_block.reload).to be_cancelled
      expect(availability_block.cancelled_at).to be_present
    end

    it "does not delete generated slots" do
      Availability::GenerateSlots.new(
        availability_block
      ).call

      slot_ids = availability_block.appointment_slots.pluck(:id)

      described_class.new(
        availability_block: availability_block
      ).call

      expect(
        AppointmentSlot.where(id: slot_ids).pluck(:id)
      ).to match_array(slot_ids)
    end

    it "is idempotent when already cancelled" do
      original_time = 1.hour.ago

      availability_block.update!(
        cancelled_at: original_time
      )

      described_class.new(
        availability_block: availability_block
      ).call

      expect(
        availability_block.reload.cancelled_at
      ).to be_within(1.second).of(original_time)
    end

    context "when the availability has a booked appointment" do
      let(:patient) do
        Patient.create!(
          practice: practice,
          patient_number: "TEST-001",
          first_name: "Test",
          last_name: "Patient",
          date_of_birth: Date.new(1990, 1, 1)
        )
      end

      before do
        Availability::GenerateSlots.new(
          availability_block
        ).call

        slot = availability_block.appointment_slots.first

        Appointment.create!(
          practice: practice,
          appointment_slot: slot,
          patient: patient,
          clinician: clinician,
          status: "booked",
          booked_at: Time.current
        )
      end

      it "does not cancel the availability block" do
        expect {
          described_class.new(
            availability_block: availability_block
          ).call
        }.to raise_error(
          Availability::CancelBlock::Unavailable,
          "Availability with booked appointments cannot be cancelled."
        )

        expect(
          availability_block.reload.cancelled_at
        ).to be_nil
      end
    end
  end
end
