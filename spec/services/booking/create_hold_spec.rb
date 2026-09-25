require "rails_helper"

RSpec.describe Booking::CreateHold do
  let!(:practice) do
    Practice.create!(
      name: "Test Practice",
      timezone: "Europe/London",
      currency: "GBP",
      country_code: "GB"
    )
  end

  let!(:clinician_user) do
    User.create!(
      email: "doctor@example.com",
      password: "password123"
    )
  end

  let!(:clinician) do
    StaffMember.create!(
      practice: practice,
      user: clinician_user,
      staff_type: "doctor",
      default_appointment_duration: 20
    )
  end

  let!(:patient) do
    Patient.create!(
      practice: practice,
      patient_number: "P001",
      first_name: "Test",
      last_name: "Patient",
      date_of_birth: Date.new(1990, 1, 1)
    )
  end

  let!(:availability_block) do
    AvailabilityBlock.create!(
      practice: practice,
      clinician: clinician,
      starts_at: Time.zone.parse("2026-10-01 09:00"),
      ends_at: Time.zone.parse("2026-10-01 10:00"),
      slot_duration_minutes: 20
    )
  end

  let!(:appointment_slot) do
    AppointmentSlot.create!(
      practice: practice,
      clinician: clinician,
      availability_block: availability_block,
      starts_at: Time.zone.parse("2026-10-01 09:00"),
      ends_at: Time.zone.parse("2026-10-01 09:20")
    )
  end

  describe "#call" do
    it "creates a hold for the patient" do
      hold = described_class.new(
        appointment_slot: appointment_slot,
        patient: patient
      ).call

      expect(hold).to be_persisted
      expect(hold.patient).to eq(patient)
      expect(hold.appointment_slot).to eq(appointment_slot)
    end

    it "does not allow another active hold on the same slot" do
      described_class.new(
        appointment_slot: appointment_slot,
        patient: patient
      ).call

      second_patient = Patient.create!(
        practice: practice,
        patient_number: "P002",
        first_name: "Another",
        last_name: "Patient",
        date_of_birth: Date.new(1985, 1, 1)
      )

      expect {
        described_class.new(
          appointment_slot: appointment_slot,
          patient: second_patient
        ).call
      }.to raise_error(
        Booking::CreateHold::SlotUnavailable
      )
    end
    it "replaces an expired hold" do
      old_hold = AppointmentHold.create!(
        appointment_slot: appointment_slot,
        patient: patient,
        expires_at: 1.minute.ago
      )

      second_patient = Patient.create!(
        practice: practice,
        patient_number: "P002",
        first_name: "Another",
        last_name: "Patient",
        date_of_birth: Date.new(1985, 1, 1)
      )

      new_hold = described_class.new(
        appointment_slot: appointment_slot,
        patient: second_patient
      ).call

      expect(AppointmentHold.exists?(old_hold.id)).to be(false)

      expect(new_hold).to be_persisted
      expect(new_hold.patient).to eq(second_patient)
      expect(new_hold.appointment_slot).to eq(appointment_slot)
    end
    it "does not allow a hold on an already booked slot" do
      Appointment.create!(
        practice: practice,
        appointment_slot: appointment_slot,
        patient: patient,
        clinician: clinician,
        status: "booked",
        booked_at: Time.current
      )

      second_patient = Patient.create!(
        practice: practice,
        patient_number: "P002",
        first_name: "Another",
        last_name: "Patient",
        date_of_birth: Date.new(1985, 1, 1)
      )

      expect {
        described_class.new(
          appointment_slot: appointment_slot,
          patient: second_patient
        ).call
      }.to raise_error(
        Booking::CreateHold::SlotUnavailable,
        "Appointment slot has already been booked"
      )

      expect(appointment_slot.reload.appointment_hold).to be_nil
    end
    it "allows only one patient to hold a slot when requests are concurrent" do
      second_patient = Patient.create!(
        practice: practice,
        patient_number: "P002",
        first_name: "Another",
        last_name: "Patient",
        date_of_birth: Date.new(1985, 1, 1)
      )

      results = Queue.new

      threads = [ patient, second_patient ].map do |current_patient|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            slot = AppointmentSlot.find(appointment_slot.id)
            current_patient = Patient.find(current_patient.id)

            begin
              hold = described_class.new(
                appointment_slot: slot,
                patient: current_patient
              ).call

              results << [ :success, hold.id ]
            rescue Booking::CreateHold::SlotUnavailable
              results << [ :unavailable, nil ]
            end
          end
        end
      end

      threads.each(&:join)

      outcomes = 2.times.map { results.pop }

      expect(outcomes.count { |result, _| result == :success }).to eq(1)
      expect(outcomes.count { |result, _| result == :unavailable }).to eq(1)

      expect(
        AppointmentHold.where(appointment_slot: appointment_slot).count
      ).to eq(1)
    end
  end
end
