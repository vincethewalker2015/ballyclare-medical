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
  it "requires a refund when availability cancellation wins the race against Stripe success" do
    slot = create(:appointment_slot)
    patient = create(:patient, practice: slot.practice)
    hold = slot.hold_for!(patient: patient)
    payment = Payment.create!(
      appointment_hold: hold, patient: patient, provider: "stripe",
      provider_payment_id: "pi_cancel_race",
      amount_cents: 6500, currency: slot.practice.currency,
      status: "processing", idempotency_key: SecureRandom.uuid
    )
    intent = instance_double(Stripe::PaymentIntent,
      id: "pi_cancel_race", amount_received: 6500,
      currency: payment.currency.downcase)

    cancellation_locked = Queue.new
    release_cancellation = Queue.new
    payment_pid = Queue.new
    cancellation_thread = nil
    payment_thread = nil

    begin
      cancellation_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          AvailabilityBlock.transaction do
            StaffMember.lock.find(slot.clinician_id)
            cancellation_locked << true
            release_cancellation.pop
            Availability::CancelBlock.new(
              availability_block: AvailabilityBlock.find(slot.availability_block_id)
            ).call
          end
        end
      end
      Timeout.timeout(10) { cancellation_locked.pop }

      payment_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          payment_pid << connection.select_value("SELECT pg_backend_pid()")
          Payments::HandleSucceeded.new(payment_intent: intent).call
        end
      end
      pid = Timeout.timeout(10) { payment_pid.pop }

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
      expect(payment_thread.join(0)).to be_nil

      release_cancellation << true
      Timeout.timeout(10) { cancellation_thread.value }
      Timeout.timeout(10) { payment_thread.value }

      expect(AvailabilityBlock.find(slot.availability_block_id)).to be_cancelled
      expect(payment.reload.status).to eq("requires_refund")
      expect(payment.appointment_id).to be_nil
      expect(Appointment.where(appointment_slot_id: slot.id).count).to eq(0)
      expect(AppointmentCharge.count).to eq(0)
    ensure
      release_cancellation << true
      [cancellation_thread, payment_thread].compact.each { |thread| thread.join(10) }
    end
  end

  it "rejects availability cancellation when Stripe booking completion wins the race" do
    slot = create(:appointment_slot)
    patient = create(:patient, practice: slot.practice)
    hold = slot.hold_for!(patient: patient)
    payment = Payment.create!(
      appointment_hold: hold, patient: patient, provider: "stripe",
      provider_payment_id: "pi_booking_wins_cancel_race",
      amount_cents: 6500, currency: slot.practice.currency,
      status: "processing", idempotency_key: SecureRandom.uuid
    )
    intent = instance_double(Stripe::PaymentIntent,
      id: "pi_booking_wins_cancel_race", amount_received: 6500,
      currency: payment.currency.downcase)

    booking_locked = Queue.new
    release_booking = Queue.new
    cancellation_pid = Queue.new
    booking_thread = nil
    cancellation_thread = nil

    begin
      booking_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Payment.transaction do
            StaffMember.lock.find(slot.clinician_id)
            booking_locked << true
            release_booking.pop
            Payments::HandleSucceeded.new(payment_intent: intent).call
          end
        end
      end
      Timeout.timeout(10) { booking_locked.pop }

      cancellation_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          cancellation_pid << connection.select_value("SELECT pg_backend_pid()")
          begin
            Availability::CancelBlock.new(
              availability_block: AvailabilityBlock.find(slot.availability_block_id)
            ).call
            :cancelled
          rescue Availability::CancelBlock::Unavailable
            :rejected
          end
        end
      end
      pid = Timeout.timeout(10) { cancellation_pid.pop }

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
      expect(cancellation_thread.join(0)).to be_nil

      release_booking << true
      Timeout.timeout(10) { booking_thread.value }
      expect(Timeout.timeout(10) { cancellation_thread.value }).to eq(:rejected)

      expect(AvailabilityBlock.find(slot.availability_block_id)).to be_active
      expect(payment.reload.status).to eq("succeeded")
      expect(payment.appointment_id).to be_present
      expect(Appointment.where(appointment_slot_id: slot.id).count).to eq(1)
      expect(AppointmentCharge.where(appointment_id: payment.appointment_id).count).to eq(1)
    ensure
      release_booking << true
      [booking_thread, cancellation_thread].compact.each { |thread| thread.join(10) }
    end
  end

end
