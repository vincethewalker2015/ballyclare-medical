require "rails_helper"

RSpec.describe "Concurrent appointment rescheduling", :concurrency do
  it "allows only one of two simultaneous reschedules into the same slot" do
    practice = create(:practice)
    clinician = create(:staff_member, practice: practice)
    block = create(:availability_block, practice: practice, clinician: clinician)
    starts_at = block.starts_at + 20.minutes

    original_slots = [0, 1].map do |offset|
      create(:appointment_slot, practice: practice, clinician: clinician,
        availability_block: block, starts_at: starts_at + offset * 20.minutes,
        ends_at: starts_at + (offset + 1) * 20.minutes)
    end
    replacement = create(:appointment_slot, practice: practice, clinician: clinician,
      availability_block: block, starts_at: starts_at + 60.minutes,
      ends_at: starts_at + 80.minutes)
    appointments = original_slots.map do |slot|
      create(:appointment, practice: practice, clinician: clinician, appointment_slot: slot)
    end
    actor = create(:user)

    ready = Queue.new
    go = Queue.new
    threads = appointments.map do |appointment|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          go.pop
          begin
            Appointments::Reschedule.new(
              appointment: Appointment.find(appointment.id),
              replacement_slot: AppointmentSlot.find(replacement.id),
              staff_user: User.find(actor.id)
            ).call
            :success
          rescue Appointments::Reschedule::NotAllowed
            :rejected
          end
        end
      end
    end

    2.times { ready.pop }
    2.times { go << true }
    outcomes = threads.map(&:value)

    expect(outcomes.sort).to eq(%i[rejected success])
    expect(Appointment.where(appointment_slot_id: replacement.id)
      .where.not(status: "cancelled").count).to eq(1)
    expect(appointments.count { |appointment| original_slots.map(&:id).include?(appointment.reload.appointment_slot_id) }).to eq(1)
    expect(AuditEvent.where(action: "appointment.rescheduled", auditable_id: appointments.map(&:id)).count).to eq(1)
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
  end
end
