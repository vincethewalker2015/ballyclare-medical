require "rails_helper"

RSpec.describe Availability::GenerateSlots do
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
        default_appointment_duration: 20
      )
    end

    let!(:availability_block) do
      AvailabilityBlock.create!(
        practice: practice,
        clinician: doctor,
        starts_at: Time.zone.parse("2026-10-01 09:00"),
        ends_at: Time.zone.parse("2026-10-01 12:00"),
        slot_duration_minutes: 20,
        bookable_online: true
      )
    end

    it "generates 20-minute appointment slots" do
      expect {
        described_class.new(availability_block).call
      }.to change(AppointmentSlot, :count).by(9)
    end

    it "does not generate duplicate slots when called again" do
      described_class.new(availability_block).call

      expect {
        described_class.new(availability_block).call
      }.not_to change(AppointmentSlot, :count)
    end

    it "generates the correct first and last slots" do
      described_class.new(availability_block).call

      slots = availability_block.appointment_slots.order(:starts_at)

      expect(slots.first.starts_at)
        .to eq(Time.zone.parse("2026-10-01 09:00"))

      expect(slots.first.ends_at)
        .to eq(Time.zone.parse("2026-10-01 09:20"))

      expect(slots.last.starts_at)
        .to eq(Time.zone.parse("2026-10-01 11:40"))

      expect(slots.last.ends_at)
        .to eq(Time.zone.parse("2026-10-01 12:00"))
    end
    it "does not create a slot that extends beyond the availability block" do
      availability_block.update!(
        starts_at: Time.zone.parse("2026-10-01 09:00"),
        ends_at: Time.zone.parse("2026-10-01 10:10"),
        slot_duration_minutes: 20
      )

      described_class.new(availability_block).call

      slots = availability_block.appointment_slots.order(:starts_at)

      expect(slots.count).to eq(3)
      expect(slots.last.starts_at).to eq(Time.zone.parse("2026-10-01 09:40"))
      expect(slots.last.ends_at).to eq(Time.zone.parse("2026-10-01 10:00"))
    end
  end
end
