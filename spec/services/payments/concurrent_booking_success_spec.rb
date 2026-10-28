require "rails_helper"
require "timeout"

RSpec.describe "Concurrent Stripe booking success", :concurrency do
  self.use_transactional_tests = false

  it "creates one appointment and charge when two sessions process the same successful intent" do
    slot = create(:appointment_slot)
    patient = create(:patient, practice: slot.practice)
    hold = slot.hold_for!(patient: patient)
    payment = Payment.create!(
      appointment_hold: hold, patient: patient, provider: "stripe",
      provider_payment_id: "pi_concurrent_booking_success",
      amount_cents: 6500, currency: slot.practice.currency,
      status: "processing", idempotency_key: SecureRandom.uuid
    )
    intent = instance_double(Stripe::PaymentIntent,
      id: "pi_concurrent_booking_success",
      amount_received: 6500, currency: payment.currency.downcase)

    lock_acquired = Queue.new
    release_first = Queue.new
    second_pid = Queue.new
    first = nil
    second = nil

    begin
      first = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Payment.transaction do
            Payment.lock.find(payment.id)
            lock_acquired << true
            release_first.pop
            Payments::HandleSucceeded.new(payment_intent: intent).call
          end
        end
      end
      Timeout.timeout(10) { lock_acquired.pop }

      second = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          second_pid << connection.select_value("SELECT pg_backend_pid()")
          Payments::HandleSucceeded.new(payment_intent: intent).call
        end
      end
      pid = Timeout.timeout(10) { second_pid.pop }

      Timeout.timeout(10) do
        loop do
          blocked = ActiveRecord::Base.connection_pool.with_connection do |connection|
            connection.select_value(ActiveRecord::Base.sanitize_sql_array([
              "SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE pid = ? AND datname = current_database() AND wait_event_type = 'Lock')",
              pid
            ]))
          end
          break if blocked == true || blocked == "t"
          Thread.pass
        end
      end
      expect(second.join(0)).to be_nil

      release_first << true
      Timeout.timeout(10) { first.value }
      Timeout.timeout(10) { second.value }

      payment.reload
      expect(payment.status).to eq("succeeded")
      expect(payment.appointment).to be_present
      expect(Appointment.where(appointment_slot_id: slot.id).count).to eq(1)
      expect(AppointmentCharge.where(appointment_id: payment.appointment_id).count).to eq(1)
    ensure
      release_first << true
      [first, second].compact.each { |thread| thread.join(10) }
    end
  end
end
