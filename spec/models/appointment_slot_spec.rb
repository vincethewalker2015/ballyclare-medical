require "rails_helper"

RSpec.describe AppointmentSlot do
  describe "validations" do
    subject(:appointment_slot) { described_class.new }

    let(:practice) { create(:practice) }
    let(:clinician) { create(:staff_member, practice: practice) }
    let(:availability_block) { create(:availability_block, practice: practice, clinician: clinician) }

    it "is not valid without a starts_at" do
      appointment_slot.assign_attributes(
        practice: practice,
        clinician: clinician,
        availability_block: availability_block,
        ends_at: 1.hour.from_now
      )
      expect(appointment_slot).not_to be_valid
    end

    it "has an error on starts_at" do
      appointment_slot.assign_attributes(
        practice: practice,
        clinician: clinician,
        availability_block: availability_block,
        ends_at: 1.hour.from_now
      )
      appointment_slot.valid?
      expect(appointment_slot.errors[:starts_at]).to be_present
    end

    it "is not valid without an ends_at" do
      appointment_slot.assign_attributes(
        practice: practice,
        clinician: clinician,
        availability_block: availability_block,
        starts_at: Time.current
      )
      expect(appointment_slot).not_to be_valid
    end

    it "has an error on ends_at" do
      appointment_slot.assign_attributes(
        practice: practice,
        clinician: clinician,
        availability_block: availability_block,
        starts_at: Time.current
      )
      appointment_slot.valid?
      expect(appointment_slot.errors[:ends_at]).to be_present
    end

    it "is not valid when ends_at is before starts_at" do
      appointment_slot.assign_attributes(
        practice: practice,
        clinician: clinician,
        availability_block: availability_block,
        starts_at: 2.hours.from_now,
        ends_at: 1.hour.from_now
      )
      expect(appointment_slot).not_to be_valid
    end

    it "has an error on ends_at when it is before starts_at" do
      appointment_slot.assign_attributes(
        practice: practice,
        clinician: clinician,
        availability_block: availability_block,
        starts_at: 2.hours.from_now,
        ends_at: 1.hour.from_now
      )
      appointment_slot.valid?
      expect(appointment_slot.errors[:ends_at]).to include("must be after starts_at")
    end
  end

  describe ".upcoming" do
    it "includes slots starting in the future" do
      future_slot = create(:appointment_slot, starts_at: 1.hour.from_now, ends_at: 2.hours.from_now)
      expect(described_class.upcoming).to include(future_slot)
    end

    it "excludes slots starting in the past" do
      past_slot = create(:appointment_slot, starts_at: 2.hours.ago, ends_at: 1.hour.ago)
      expect(described_class.upcoming).not_to include(past_slot)
    end
  end

  describe "#hold_for!" do
    let(:practice) { create(:practice) }
    let(:clinician) { create(:staff_member, practice: practice) }
    let(:availability_block) do
      create(
        :availability_block,
        practice: practice,
        clinician: clinician,
        starts_at: Time.zone.parse("2026-10-01 09:00"),
        ends_at: Time.zone.parse("2026-10-01 10:00")
      )
    end
    let(:appointment_slot) do
      create(
        :appointment_slot,
        practice: practice,
        clinician: clinician,
        availability_block: availability_block,
        starts_at: Time.zone.parse("2026-10-01 09:00"),
        ends_at: Time.zone.parse("2026-10-01 09:20")
      )
    end
    let(:patient) { create(:patient, practice: practice) }

    it "creates a hold for the patient" do
      hold = appointment_slot.hold_for!(patient: patient)

      expect(hold).to be_persisted
      expect(hold.patient).to eq(patient)
      expect(hold.appointment_slot).to eq(appointment_slot)
    end

    it "does not allow another active hold on the same slot" do
      appointment_slot.hold_for!(patient: patient)

      second_patient = create(:patient, practice: practice)

      expect {
        appointment_slot.hold_for!(patient: second_patient)
      }.to raise_error(AppointmentSlot::Unavailable)
    end

    it "replaces an expired hold" do
      old_hold = create(
        :appointment_hold,
        appointment_slot: appointment_slot,
        patient: patient,
        expires_at: 1.minute.ago
      )
      second_patient = create(:patient, practice: practice)

      new_hold = appointment_slot.hold_for!(patient: second_patient)

      expect(AppointmentHold.exists?(old_hold.id)).to be(false)
      expect(new_hold).to be_persisted
      expect(new_hold.patient).to eq(second_patient)
      expect(new_hold.appointment_slot).to eq(appointment_slot)
    end

    it "does not allow a hold on an already booked slot" do
      create(
        :appointment,
        practice: practice,
        appointment_slot: appointment_slot,
        patient: patient,
        clinician: clinician
      )
      second_patient = create(:patient, practice: practice)

      expect {
        appointment_slot.hold_for!(patient: second_patient)
      }.to raise_error(
        AppointmentSlot::Unavailable,
        "Appointment slot has already been booked"
      )

      expect(appointment_slot.reload.appointment_hold).to be_nil
    end

    it "allows only one patient to hold a slot when requests are concurrent" do
      second_patient = create(:patient, practice: practice)
      results = Queue.new

      threads = [ patient, second_patient ].map do |current_patient|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            slot = described_class.find(appointment_slot.id)
            current_patient = Patient.find(current_patient.id)

            begin
              hold = slot.hold_for!(patient: current_patient)
              results << [ :success, hold.id ]
            rescue AppointmentSlot::Unavailable
              results << [ :unavailable, nil ]
            end
          end
        end
      end

      threads.each(&:join)

      outcomes = 2.times.map { results.pop }

      expect(outcomes.count { |result, _| result == :success }).to eq(1)
      expect(outcomes.count { |result, _| result == :unavailable }).to eq(1)
      expect(AppointmentHold.where(appointment_slot: appointment_slot).count).to eq(1)
    end
    it "does not allow a patient from another practice to hold the slot" do
      other_practice = Practice.create!(
        name: "Other Practice",
        timezone: "America/New_York",
        currency: "USD",
        country_code: "US"
      )

      other_patient = Patient.create!(
        practice: other_practice,
        patient_number: "P001",
        first_name: "Other",
        last_name: "Patient",
        date_of_birth: Date.new(1990, 1, 1)
      )

      expect {
        appointment_slot.hold_for!(patient: other_patient)
      }.to raise_error(
        AppointmentSlot::PracticeMismatch
      )

      expect(appointment_slot.reload.appointment_hold).to be_nil
    end
  end
end
