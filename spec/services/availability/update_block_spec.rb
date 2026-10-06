require "rails_helper"

RSpec.describe Availability::UpdateBlock do
  describe "#call" do
    let!(:practice) do
      Practice.create!(
        name: "Test Practice",
        timezone: "Europe/London",
        currency: "GBP",
        country_code: "GB"
      )
    end

    let!(:user) do
      User.create!(
        email: "doctor@example.com",
        password: "password123"
      )
    end

    let!(:doctor) do
      StaffMember.create!(
        practice: practice,
        user: user,
        staff_type: "doctor",
        default_appointment_duration: 30
      )
    end

    let!(:availability_block) do
      AvailabilityBlock.create!(
        practice: practice,
        clinician: doctor,
        starts_at: Time.zone.parse("2026-10-20 09:00"),
        ends_at: Time.zone.parse("2026-10-20 12:00"),
        slot_duration_minutes: 30,
        bookable_online: true
      )
    end

    before do
      Availability::GenerateSlots.new(
        availability_block
      ).call
    end

    def update_block
      described_class.new(
        availability_block: availability_block,
        clinician: doctor,
        starts_at: Time.zone.parse("2026-10-20 10:00"),
        ends_at: Time.zone.parse("2026-10-20 13:00"),
        slot_duration_minutes: 30,
        bookable_online: false
      ).call
    end

    context "when the generated slots are unused" do
      it "updates the availability block" do
        update_block

        availability_block.reload

        expect(availability_block).to have_attributes(
          clinician: doctor,
          starts_at: Time.zone.parse("2026-10-20 10:00"),
          ends_at: Time.zone.parse("2026-10-20 13:00"),
          slot_duration_minutes: 30,
          bookable_online: false
        )
      end

      it "replaces the generated appointment slots" do
        original_slot_ids =
          availability_block.appointment_slots.pluck(:id)

        update_block

        slots = availability_block
          .appointment_slots
          .reload
          .order(:starts_at)

        expect(slots.count).to eq(6)

        expect(slots.pluck(:id) & original_slot_ids).to be_empty

        expect(slots.first.starts_at)
          .to eq(Time.zone.parse("2026-10-20 10:00"))

        expect(slots.last.ends_at)
          .to eq(Time.zone.parse("2026-10-20 13:00"))
      end
    end

    context "when a generated slot has an appointment" do
      let!(:patient) do
        Patient.create!(
          practice: practice,
          patient_number: "TEST-001",
          first_name: "Test",
          last_name: "Patient",
          date_of_birth: Date.new(1990, 1, 1)
        )
      end

      before do
        slot = availability_block
          .appointment_slots
          .order(:starts_at)
          .first

        Appointment.create!(
          practice: practice,
          appointment_slot: slot,
          patient: patient,
          clinician: doctor,
          status: "booked",
          booked_at: Time.current
        )
      end

      it "does not allow the availability to be rescheduled" do
        expect {
          update_block
        }.to raise_error(
          Availability::UpdateBlock::Unavailable,
          "Availability with booked appointments cannot be rescheduled."
        )
      end

      it "does not change the availability block or its slots" do
        original_attributes =
          availability_block.attributes.slice(
            "clinician_id",
            "starts_at",
            "ends_at",
            "slot_duration_minutes",
            "bookable_online"
          )

        original_slot_ids =
          availability_block.appointment_slots.pluck(:id)

        expect {
          update_block
        }.to raise_error(Availability::UpdateBlock::Unavailable)

        expect(
          availability_block.reload.attributes.slice(
            "clinician_id",
            "starts_at",
            "ends_at",
            "slot_duration_minutes",
            "bookable_online"
          )
        ).to eq(original_attributes)

        expect(
          availability_block.appointment_slots.pluck(:id)
        ).to match_array(original_slot_ids)
      end
    end

    context "when a generated slot has an expired appointment hold" do
      let!(:patient) do
        Patient.create!(
          practice: practice,
          patient_number: "TEST-002",
          first_name: "Held",
          last_name: "Patient",
          date_of_birth: Date.new(1990, 1, 1)
        )
      end

      before do
        slot = availability_block
          .appointment_slots
          .order(:starts_at)
          .first

        AppointmentHold.create!(
          appointment_slot: slot,
          patient: patient,
          expires_at: 1.hour.ago
        )
      end

      it "does not allow the availability to be rescheduled" do
        expect {
          update_block
        }.to raise_error(
          Availability::UpdateBlock::Unavailable,
          "Availability with appointment hold history cannot be rescheduled."
        )
      end

      it "preserves the historical hold and generated slots" do
        original_slot_ids =
          availability_block.appointment_slots.pluck(:id)

        expect {
          update_block
        }.to raise_error(Availability::UpdateBlock::Unavailable)

        expect(AppointmentHold.count).to eq(1)

        expect(
          availability_block
            .appointment_slots
            .reload
            .pluck(:id)
        ).to match_array(original_slot_ids)
      end
    end
  end
end
