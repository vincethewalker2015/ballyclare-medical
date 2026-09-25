require "rails_helper"

RSpec.describe Payments::Create do
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

  let!(:hold) do
    AppointmentHold.create!(
      appointment_slot: appointment_slot,
      patient: patient,
      expires_at: 10.minutes.from_now
    )
  end

  describe "#call" do
    it "creates a pending payment for the hold" do
      payment = described_class.new(
        hold: hold,
        amount_cents: 5000,
        currency: "GBP",
        provider: "test"
      ).call

      expect(payment).to be_persisted
      expect(payment.appointment_hold).to eq(hold)
      expect(payment.appointment).to be_nil
      expect(payment.patient).to eq(patient)
      expect(payment.amount_cents).to eq(5000)
      expect(payment.currency).to eq("GBP")
      expect(payment.provider).to eq("test")
      expect(payment.status).to eq("pending")
      expect(payment.idempotency_key).to be_present
    end

    it "does not create a payment for an expired hold" do
      hold.update!(expires_at: 1.minute.ago)

      expect {
        described_class.new(
          hold: hold,
          amount_cents: 5000,
          currency: "GBP",
          provider: "test"
        ).call
      }.to raise_error(
        Payments::Create::HoldExpired,
        "Appointment hold has expired"
      )

      expect(Payment.count).to eq(0)
    end

    it "does not create a payment with a different currency from the practice" do
      expect {
        described_class.new(
          hold: hold,
          amount_cents: 5000,
          currency: "USD",
          provider: "test"
        ).call
      }.to raise_error(
        Payments::Create::PracticeMismatch,
        "Payment currency must match the practice currency"
      )

      expect(Payment.count).to eq(0)
    end
  end
end
