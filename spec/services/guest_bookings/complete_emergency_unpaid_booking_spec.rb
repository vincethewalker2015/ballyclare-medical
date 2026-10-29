require "rails_helper"
require "active_support/testing/time_helpers"

RSpec.describe GuestBookings::CompleteEmergencyUnpaidBooking do
  include ActiveSupport::Testing::TimeHelpers
  let(:practice) { create(:practice) }
  let(:clinician) { create(:staff_member, practice: practice, staff_type: "doctor") }
  let(:administrator) do
    create(:staff_member, practice: practice, staff_type: "administrator",
      access_level: "senior_staff_admin")
  end
  let(:starts_at) { 3.days.from_now.change(hour: 10, min: 0) }
  let(:availability_block) do
    create(:availability_block, practice: practice, clinician: clinician,
      starts_at: starts_at - 1.hour, ends_at: starts_at + 1.hour, bookable_online: true)
  end
  let(:slot) do
    create(:appointment_slot, practice: practice, clinician: clinician,
      availability_block: availability_block, starts_at: starts_at,
      ends_at: starts_at + 20.minutes)
  end
  let(:guest) do
    GuestBooking.create!(
      practice: practice, appointment_slot: slot,
      first_name: "Guest", last_name: "Visitor",
      date_of_birth: Date.new(1990, 1, 1),
      email: "visitor@example.com", phone: "07700900123",
      consultation_reason: "Consultation", status: "draft",
      expires_at: 30.minutes.from_now
    )
  end

  it "books an outstanding-charge appointment without contacting Stripe during a declared outage" do
    create(:consultation_fee, practice: practice, clinician_type: "doctor")
    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: administrator, reason: "Stripe outage independently confirmed"
    )
    hold = GuestBookings::ReserveSlot.new(guest_booking: guest).call

    expect(Stripe::PaymentIntent).not_to receive(:create)
    expect {
      @appointment = described_class.new(hold: hold).call
    }.to change(Appointment, :count).by(1)
      .and change(Patient, :count).by(1)
      .and change(Payment, :count).by(0)

    expect(@appointment.status).to eq("booked")
    expect(@appointment.patient.patient_type).to eq("external")
    expect(@appointment.appointment_charges.sole.amount_cents).to eq(6_500)
    expect(@appointment.appointment_charges.sole.status).to eq("active")
    expect(guest.reload.status).to eq("completed")
    expect(AppointmentHold.exists?(hold.id)).to be(false)
  end
  it "rejects a repeated completion without creating another appointment, patient or charge" do
    create(:consultation_fee, practice: practice, clinician_type: "doctor")
    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: administrator, reason: "Stripe outage independently confirmed"
    )
    hold = GuestBookings::ReserveSlot.new(guest_booking: guest).call
    appointment = described_class.new(hold: hold).call

    expect {
      expect { described_class.new(hold: hold).call }
        .to raise_error(described_class::Unavailable)
    }.not_to change {
      [ Appointment.count, Patient.count, AppointmentCharge.count ]
    }

    expect(Appointment.where(appointment_slot: slot).sole.id).to eq(appointment.id)
  end

  %w[pending processing succeeded failed cancelled requires_refund].each do |status|
    it "rejects emergency booking when a #{status} Stripe payment already exists" do
      create(:consultation_fee, practice: practice, clinician_type: "doctor")
      Payments::StripeOutageDeclaration.activate!(
        practice: practice, actor: administrator, reason: "Stripe outage independently confirmed"
      )
      hold = GuestBookings::ReserveSlot.new(guest_booking: guest).call
      Payment.create!(
        appointment_hold: hold,
        guest_booking: guest,
        provider: "stripe",
        currency: "GBP",
        amount_cents: 6_500,
        status: status,
        idempotency_key: SecureRandom.uuid
      )

      expect {
        expect { described_class.new(hold: hold).call }
          .to raise_error(described_class::Unavailable, /not permitted/)
      }.not_to change {
        [ Appointment.count, Patient.count, AppointmentCharge.count ]
      }

      expect(guest.reload.status).to eq("payment_pending")
      expect(AppointmentHold.exists?(hold.id)).to be(true)
    end
  end

  it "rejects an expired hold without creating a patient, appointment or charge" do
    create(:consultation_fee, practice: practice, clinician_type: "doctor")
    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: administrator, reason: "Stripe outage independently confirmed"
    )
    hold = GuestBookings::ReserveSlot.new(guest_booking: guest).call
    hold.update!(expires_at: 1.minute.ago)

    expect {
      expect { described_class.new(hold: hold).call }
        .to raise_error(described_class::Unavailable, /expired/)
    }.not_to change {
      [ Appointment.count, Patient.count, AppointmentCharge.count ]
    }
    expect(guest.reload.status).to eq("payment_pending")
  end

  it "rejects a guest booking whose expiry has passed even if its hold is still valid" do
    create(:consultation_fee, practice: practice, clinician_type: "doctor")
    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: administrator, reason: "Stripe outage independently confirmed"
    )
    hold = GuestBookings::ReserveSlot.new(guest_booking: guest).call
    guest.update!(expires_at: 1.minute.ago)

    expect {
      expect { described_class.new(hold: hold).call }
        .to raise_error(described_class::Unavailable, /expired/)
    }.not_to change {
      [ Appointment.count, Patient.count, AppointmentCharge.count ]
    }
    expect(AppointmentHold.exists?(hold.id)).to be(true)
  end

  it "allows only one completion when two guest holds compete for the same slot" do
    create(:consultation_fee, practice: practice, clinician_type: "doctor")
    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: administrator, reason: "Stripe outage independently confirmed"
    )
    first_hold = GuestBookings::ReserveSlot.new(guest_booking: guest).call
    other_guest = GuestBooking.create!(
      practice: practice, appointment_slot: slot,
      first_name: "Other", last_name: "Visitor",
      date_of_birth: Date.new(1991, 1, 1),
      email: "other@example.com", phone: "07700900124",
      consultation_reason: "Another consultation", status: "payment_pending",
      expires_at: 20.minutes.from_now
    )
    competing_hold = AppointmentHold.create!(
      appointment_slot: slot, guest_booking: other_guest,
      expires_at: 20.minutes.from_now
    )

    first_appointment = described_class.new(hold: first_hold).call

    expect {
      expect { described_class.new(hold: competing_hold).call }
        .to raise_error(described_class::Unavailable, /already booked/)
    }.not_to change {
      [ Appointment.count, Patient.count, AppointmentCharge.count ]
    }

    expect(Appointment.where(appointment_slot: slot).sole).to eq(first_appointment)
    expect(other_guest.reload.status).to eq("payment_pending")
    expect(AppointmentHold.exists?(competing_hold.id)).to be(true)
  end

  it "allows exactly one of two simultaneous guest completions for the same slot", :concurrency do
    create(:consultation_fee, practice: practice, clinician_type: "doctor")
    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: administrator, reason: "Stripe outage independently confirmed"
    )
    first_hold = GuestBookings::ReserveSlot.new(guest_booking: guest).call
    other_guest = GuestBooking.create!(
      practice: practice, appointment_slot: slot,
      first_name: "Concurrent", last_name: "Visitor",
      date_of_birth: Date.new(1991, 1, 1),
      email: "concurrent@example.com", phone: "07700900125",
      consultation_reason: "Another consultation", status: "payment_pending",
      expires_at: 20.minutes.from_now
    )
    second_hold = AppointmentHold.create!(
      appointment_slot: slot, guest_booking: other_guest,
      expires_at: 20.minutes.from_now
    )

    ready = Queue.new
    start = Queue.new
    workers = [ first_hold.id, second_hold.id ].map do |hold_id|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            described_class.new(hold: AppointmentHold.find(hold_id)).call
            :booked
          rescue described_class::Unavailable
            :unavailable
          end
        end
      end
    end

    begin
      2.times { ready.pop }
      2.times { start << true }
      expect(workers.map(&:value).sort).to eq(%i[booked unavailable].sort)
    ensure
      workers.each { |worker| worker.kill if worker.alive? }
      workers.each(&:join)
    end

    expect(Appointment.where(appointment_slot: slot).count).to eq(1)
    expect(AppointmentCharge.joins(:appointment).where(appointments: { appointment_slot_id: slot.id }).count).to eq(1)
    expect(Patient.where(practice: practice, email: [ "visitor@example.com", "concurrent@example.com" ]).count).to eq(1)
    expect(Payment.where(guest_booking: [ guest, other_guest ]).count).to eq(0)
  end

  it "clears completed guest personal details while preserving patient and unpaid charge records" do
    create(:consultation_fee, practice: practice, clinician_type: "doctor")
    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: administrator, reason: "Stripe outage independently confirmed"
    )
    hold = GuestBookings::ReserveSlot.new(guest_booking: guest).call

    appointment = described_class.new(hold: hold).call
    guest.reload

    expect(guest.status).to eq("completed")
    expect(guest.patient).to eq(appointment.patient)
    expect(guest.attributes.slice(
      "first_name", "last_name", "date_of_birth", "email", "phone", "consultation_reason"
    ).values).to all(be_nil)

    expect(appointment.patient.first_name).to eq("Guest")
    expect(appointment.patient.email).to eq("visitor@example.com")
    expect(appointment.reason).to eq("Consultation")
    expect(appointment.appointment_charges.sole.status).to eq("active")
    expect(appointment.appointment_charges.sole.amount_cents).to eq(6_500)
  end

  it "rejects emergency booking after a senior administrator deactivates the outage" do
    create(:consultation_fee, practice: practice, clinician_type: "doctor")
    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: administrator, reason: "Stripe outage independently confirmed"
    )
    hold = GuestBookings::ReserveSlot.new(guest_booking: guest).call
    Payments::StripeOutageDeclaration.deactivate!(
      practice: practice, actor: administrator, reason: "Stripe service restored"
    )

    expect {
      expect { described_class.new(hold: hold).call }
        .to raise_error(described_class::Unavailable, /not permitted/)
    }.not_to change {
      [ Appointment.count, Patient.count, AppointmentCharge.count ]
    }

    expect(guest.reload.status).to eq("payment_pending")
    expect(AppointmentHold.exists?(hold.id)).to be(true)
    expect(Payment.where(guest_booking: guest).count).to eq(0)
  end

  it "rejects emergency booking after the 30-minute outage declaration expires" do
    create(:consultation_fee, practice: practice, clinician_type: "doctor")
    hold = GuestBookings::ReserveSlot.new(guest_booking: guest).call
    hold.update!(expires_at: 45.minutes.from_now)
    guest.update!(expires_at: 45.minutes.from_now)

    travel_to Time.current.change(usec: 0) do
      Payments::StripeOutageDeclaration.activate!(
        practice: practice, actor: administrator, reason: "Stripe outage independently confirmed"
      )
      travel 31.minutes

      expect {
        expect { described_class.new(hold: hold).call }
          .to raise_error(described_class::Unavailable, /not permitted/)
      }.not_to change {
        [ Appointment.count, Patient.count, AppointmentCharge.count ]
      }
    end

    expect(guest.reload.status).to eq("payment_pending")
    expect(AppointmentHold.exists?(hold.id)).to be(true)
  end

  it "rolls back patient and appointment creation when the outstanding charge cannot be created" do
    create(:consultation_fee, practice: practice, clinician_type: "doctor")
    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: administrator, reason: "Stripe outage independently confirmed"
    )
    hold = GuestBookings::ReserveSlot.new(guest_booking: guest).call

    allow_any_instance_of(Billing::CreateCharge).to receive(:call)
      .and_raise(ActiveRecord::RecordInvalid.new(AppointmentCharge.new))

    expect {
      expect { described_class.new(hold: hold).call }
        .to raise_error(ActiveRecord::RecordInvalid)
    }.not_to change {
      [ Appointment.count, Patient.count, AppointmentCharge.count ]
    }

    expect(guest.reload.status).to eq("payment_pending")
    expect(guest.patient).to be_nil
    expect(guest.first_name).to eq("Guest")
    expect(AppointmentHold.exists?(hold.id)).to be(true)
    expect(Payment.where(guest_booking: guest).count).to eq(0)
  end
end
