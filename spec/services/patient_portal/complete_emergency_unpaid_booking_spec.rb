require "rails_helper"

RSpec.describe PatientPortal::CompleteEmergencyUnpaidBooking do
  let(:practice) { create(:practice) }
  let(:clinician) { create(:staff_member, practice: practice, staff_type: "doctor") }
  let(:patient) { create(:patient, practice: practice) }
  let(:slot) do
    appointment_slot = create(:appointment_slot, practice: practice, clinician: clinician)
    appointment_slot.availability_block.update!(bookable_online: true)
    appointment_slot
  end

  it "creates exactly one appointment and charge when two patients complete competing holds simultaneously", :concurrency do
    create(:consultation_fee, practice: practice, clinician_type: "doctor")
    senior = create(:staff_member, practice: practice,
      staff_type: "administrator", access_level: "senior_staff_admin")
    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: senior, reason: "Stripe outage independently confirmed"
    )

    first_hold = slot.hold_for!(patient: patient)
    other_patient = create(:patient, practice: practice)
    second_hold = AppointmentHold.create!(
      appointment_slot: slot, patient: other_patient, expires_at: 10.minutes.from_now
    )

    ready = Queue.new
    start = Queue.new
    workers = [first_hold.id, second_hold.id].map do |hold_id|
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
    expect(Payment.where(patient: [patient, other_patient]).count).to eq(0)
    expect(AppointmentHold.where(id: [first_hold.id, second_hold.id]).count).to eq(1)
  end
  it "rolls back the appointment when the outstanding charge cannot be created" do
    create(:consultation_fee, practice: practice, clinician_type: "doctor")
    senior = create(:staff_member, practice: practice,
      staff_type: "administrator", access_level: "senior_staff_admin")
    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: senior, reason: "Stripe outage independently confirmed"
    )
    hold = slot.hold_for!(patient: patient)

    allow_any_instance_of(Billing::CreateCharge).to receive(:call)
      .and_raise(ActiveRecord::RecordInvalid.new(AppointmentCharge.new))

    expect {
      expect { described_class.new(hold: hold).call }
        .to raise_error(ActiveRecord::RecordInvalid)
    }.not_to change {
      [Appointment.count, AppointmentCharge.count, Payment.count]
    }

    expect(AppointmentHold.exists?(hold.id)).to be(true)
    expect(Appointment.where(appointment_slot: slot).count).to eq(0)
  end

end
