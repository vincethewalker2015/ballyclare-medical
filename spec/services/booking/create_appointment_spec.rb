require "rails_helper"

RSpec.describe Booking::CreateAppointment do
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
      starts_at: 1.day.from_now,
      ends_at: 1.day.from_now + 1.hour,
      slot_duration_minutes: 20
    )
  end

  let!(:appointment_slot) do
    AppointmentSlot.create!(
      practice: practice,
      clinician: clinician,
      availability_block: availability_block,
      starts_at: availability_block.starts_at,
      ends_at: availability_block.starts_at + 20.minutes
    )
  end

  let!(:hold) do
    AppointmentHold.create!(
      appointment_slot: appointment_slot,
      patient: patient,
      expires_at: 10.minutes.from_now
    )
  end

  describe "#call" do
    it "creates an appointment from the hold" do
      appointment = described_class.new(hold: hold).call

      expect(appointment).to be_persisted
      expect(appointment.patient).to eq(patient)
      expect(appointment.clinician).to eq(clinician)
      expect(appointment.appointment_slot).to eq(appointment_slot)
      expect(appointment.practice).to eq(practice)
      expect(appointment.status).to eq("booked")
    end

    it "removes the hold after creating the appointment" do
      hold_id = hold.id

      described_class.new(hold: hold).call

      expect(AppointmentHold.exists?(hold_id)).to be(false)
    end

    it "does not create an appointment from an expired hold" do
      hold.update!(expires_at: 1.minute.ago)

      expect {
        described_class.new(hold: hold).call
      }.to raise_error(
        Booking::CreateAppointment::HoldExpired,
        "Appointment hold has expired"
      )

      expect(Appointment.where(appointment_slot: appointment_slot)).to be_empty

      # An expired hold can subsequently be cleaned/replaced by AppointmentSlot#hold_for!.
      expect(AppointmentHold.exists?(hold.id)).to be(true)
    end
    it "does not create another appointment when the slot is already booked" do
      existing_patient = Patient.create!(
        practice: practice,
        patient_number: "P002",
        first_name: "Existing",
        last_name: "Patient",
        date_of_birth: Date.new(1980, 1, 1)
      )

      existing_appointment = Appointment.create!(
        practice: practice,
        appointment_slot: appointment_slot,
        patient: existing_patient,
        clinician: clinician,
        status: "booked",
        booked_at: Time.current
      )

      expect {
        described_class.new(hold: hold).call
      }.to raise_error(
        Booking::CreateAppointment::SlotUnavailable,
        "Appointment slot has already been booked"
      )

      expect(Appointment.where(appointment_slot: appointment_slot).count).to eq(1)
      expect(Appointment.find_by(appointment_slot: appointment_slot))
        .to eq(existing_appointment)

      expect(AppointmentHold.exists?(hold.id)).to be(true)
    end
    it "keeps the hold when appointment creation fails" do
      allow(Appointment).to receive(:create!)
        .and_raise(ActiveRecord::RecordInvalid.new(Appointment.new))

      expect {
        described_class.new(hold: hold).call
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(AppointmentHold.exists?(hold.id)).to be(true)
      expect(Appointment.where(appointment_slot: appointment_slot)).to be_empty
    end

    it "rebooks a future slot after its previous appointment is cancelled" do
      original_appointment = Appointment.create!(
        practice: practice,
        appointment_slot: appointment_slot,
        patient: patient,
        clinician: clinician,
        status: "cancelled",
        booked_at: 1.day.ago
      )

      second_patient = Patient.create!(
        practice: practice,
        patient_number: "P003",
        first_name: "Second",
        last_name: "Patient",
        date_of_birth: Date.new(1992, 5, 15)
      )

      hold.update!(patient: second_patient)

      new_appointment = described_class.new(hold: hold).call

      expect(new_appointment).to be_persisted
      expect(new_appointment.status).to eq("booked")
      expect(new_appointment.patient).to eq(second_patient)
      expect(new_appointment.appointment_slot).to eq(appointment_slot)

      expect(original_appointment.reload.status).to eq("cancelled")
      expect(original_appointment).to be_persisted

      expect(
        Appointment.where(appointment_slot: appointment_slot).count
      ).to eq(2)

      expect(AppointmentHold.exists?(hold.id)).to be(false)
    end

    context "when the availability block is cancelled after the hold is created" do
      before do
        appointment_slot.availability_block.update!(
          cancelled_at: Time.current
        )
      end

      it "does not convert the hold into an appointment" do
        expect {
          described_class.new(hold: hold).call
        }.to raise_error(
          Booking::CreateAppointment::SlotUnavailable,
          "Appointment slot is no longer available"
        )

        expect(
          Appointment.exists?(appointment_slot_id: appointment_slot.id)
        ).to be(false)

        expect(AppointmentHold.exists?(hold.id)).to be(true)
      end
    end
  end
end
