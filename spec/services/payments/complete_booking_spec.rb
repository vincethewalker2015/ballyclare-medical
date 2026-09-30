require "rails_helper"

RSpec.describe Payments::CompleteBooking do
  let(:appointment_slot) { create(:appointment_slot) }

  let(:patient) do
    create(
      :patient,
      practice: appointment_slot.practice
    )
  end

  let!(:hold) do
    AppointmentHold.create!(
      appointment_slot: appointment_slot,
      patient: patient,
      expires_at: 10.minutes.from_now
    )
  end

  let!(:payment) do
    Payment.create!(
      appointment_hold: hold,
      patient: patient,
      provider: "stripe",
      provider_payment_id: "pi_test_123",
      amount_cents: 5000,
      currency: appointment_slot.practice.currency,
      status: "succeeded",
      idempotency_key: SecureRandom.uuid,
      paid_at: Time.current
    )
  end

  describe "#call" do
    it "creates an appointment from the payment hold" do
      expect {
        described_class.new(payment: payment).call
      }.to change(Appointment, :count).by(1)

      appointment = payment.reload.appointment

      expect(appointment.appointment_slot).to eq(appointment_slot)
      expect(appointment.patient).to eq(patient)
      expect(appointment.clinician).to eq(appointment_slot.clinician)
      expect(appointment.practice).to eq(appointment_slot.practice)
      expect(appointment.status).to eq("booked")
    end

    it "moves the payment from the hold to the appointment" do
      appointment = described_class.new(
        payment: payment
      ).call

      payment.reload

      expect(payment.appointment).to eq(appointment)
      expect(payment.appointment_hold).to be_nil
    end

    it "removes the appointment hold" do
      hold_id = hold.id

      described_class.new(payment: payment).call

      expect(
        AppointmentHold.exists?(hold_id)
      ).to be(false)
    end

    it "is idempotent when the booking has already been completed" do
      first_appointment = described_class.new(
        payment: payment
      ).call

      expect {
        second_appointment = described_class.new(
          payment: payment.reload
        ).call

        expect(second_appointment).to eq(first_appointment)
      }.not_to change(Appointment, :count)
    end

    it "rejects a payment that has not succeeded" do
      payment.update!(
        status: "processing",
        paid_at: nil
      )

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        Payments::CompleteBooking::PaymentNotSucceeded
      )

      expect(Appointment.exists?(
        appointment_slot_id: appointment_slot.id
      )).to be(false)

      expect(AppointmentHold.exists?(hold.id)).to be(true)
    end

    it "rejects an expired hold" do
      hold.update!(
        expires_at: 1.minute.ago
      )

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        Payments::CompleteBooking::HoldExpired
      )

      expect(Appointment.exists?(
        appointment_slot_id: appointment_slot.id
      )).to be(false)

      expect(payment.reload.appointment_hold).to eq(hold)
    end

    it "rejects an already booked slot" do
      existing_appointment = Appointment.create!(
        practice: appointment_slot.practice,
        appointment_slot: appointment_slot,
        patient: patient,
        clinician: appointment_slot.clinician,
        status: "booked",
        booked_at: Time.current
      )

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        Payments::CompleteBooking::SlotUnavailable
      )

      expect(
        Appointment.find_by(
          appointment_slot: appointment_slot
        )
      ).to eq(existing_appointment)

      expect(payment.reload.appointment).to be_nil
      expect(payment.appointment_hold).to eq(hold)
    end
    it "rolls back the booking when updating the payment fails" do
      allow(payment)
        .to receive(:update!)
        .and_raise(ActiveRecord::RecordInvalid.new(payment))

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(
        Appointment.exists?(
          appointment_slot_id: appointment_slot.id
        )
      ).to be(false)

      expect(AppointmentHold.exists?(hold.id)).to be(true)
    end
  end
end
