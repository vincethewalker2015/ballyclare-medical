
require "rails_helper"
require "timeout"

RSpec.describe "Booking and availability cancellation concurrency",
               :concurrency do
  self.use_transactional_tests = false

  def wait_for_postgres_lock(pid)
    Timeout.timeout(10) do
      loop do
        waiting = ActiveRecord::Base.connection_pool.with_connection do |connection|
          connection.select_value(
            ActiveRecord::Base.sanitize_sql_array([
              <<~SQL,
                SELECT EXISTS (
                  SELECT 1
                  FROM pg_stat_activity
                  WHERE pid = ?
                    AND datname = current_database()
                    AND wait_event_type = 'Lock'
                )
              SQL
              pid
            ])
          )
        end

        break if waiting == true || waiting == "t"

        Thread.pass
      end
    end
  end

  def create_test_records
    practice = create(
      :practice,
      name: "Concurrency Test #{SecureRandom.uuid}"
    )

    clinician = create(:staff_member, practice: practice)
    patient = create(:patient, practice: practice)
    booked_by = create(:user)

    slot = create(
      :appointment_slot,
      practice: practice,
      clinician: clinician
    )

    {
      clinician_id: clinician.id,
      patient_id: patient.id,
      booked_by_id: booked_by.id,
      slot_id: slot.id,
      availability_block_id: slot.availability_block_id
    }
  end

  def book_appointment(records)
    Booking::CreateStaffAppointment.new(
      appointment_slot: AppointmentSlot.find(records[:slot_id]),
      patient: Patient.find(records[:patient_id]),
      booked_by: User.find(records[:booked_by_id]),
      reason: "Concurrency test",
      amount_cents: 5000
    ).call
  end

  def cancel_availability(records)
    Availability::CancelBlock.new(
      availability_block: AvailabilityBlock.find(
        records[:availability_block_id]
      )
    ).call
  end

  it "waits for booking and then rejects cancellation" do
    records = create_test_records

    booking_has_lock = Queue.new
    release_booking = Queue.new
    cancellation_pid = Queue.new

    booking_thread = nil
    cancellation_thread = nil

    begin
      booking_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          AppointmentSlot.transaction do
            StaffMember.lock.find(records[:clinician_id])

            booking_has_lock << true
            release_booking.pop

            book_appointment(records)
          end
        end
      end

      Timeout.timeout(10) { booking_has_lock.pop }

      cancellation_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          cancellation_pid << connection.select_value(
            "SELECT pg_backend_pid()"
          )

          begin
            cancel_availability(records)
            :cancelled
          rescue Availability::CancelBlock::Unavailable
            :rejected
          end
        end
      end

      pid = Timeout.timeout(10) { cancellation_pid.pop }

      # Verify that this cancellation connection is blocked
      # while the booking transaction holds the clinician lock.
      wait_for_postgres_lock(pid)

      expect(cancellation_thread.join(0)).to be_nil

      release_booking << true

      Timeout.timeout(10) { booking_thread.value }

      cancellation_result = Timeout.timeout(10) do
        cancellation_thread.value
      end

      expect(cancellation_result).to eq(:rejected)

      expect(
        Appointment.exists?(
          appointment_slot_id: records[:slot_id]
        )
      ).to be(true)

      expect(
        AvailabilityBlock.find(records[:availability_block_id])
      ).to be_active
    ensure
      release_booking << true

      [ booking_thread, cancellation_thread ].compact.each do |thread|
        thread.join(10)
      end
    end
  end

  it "rejects booking when cancellation completes first" do
    records = create_test_records

    cancellation_has_lock = Queue.new
    release_cancellation = Queue.new
    booking_pid = Queue.new

    cancellation_thread = nil
    booking_thread = nil

    begin
      cancellation_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          AvailabilityBlock.transaction do
            StaffMember.lock.find(records[:clinician_id])

            cancellation_has_lock << true
            release_cancellation.pop

            cancel_availability(records)
          end
        end
      end

      Timeout.timeout(10) { cancellation_has_lock.pop }

      booking_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          booking_pid << connection.select_value(
            "SELECT pg_backend_pid()"
          )

          begin
            book_appointment(records)
            :booked
          rescue Booking::CreateStaffAppointment::SlotUnavailable
            :rejected
          end
        end
      end

      pid = Timeout.timeout(10) { booking_pid.pop }

      # Verify that this booking connection is blocked
      # while cancellation holds the clinician lock.
      wait_for_postgres_lock(pid)

      expect(booking_thread.join(0)).to be_nil

      release_cancellation << true

      Timeout.timeout(10) { cancellation_thread.value }

      booking_result = Timeout.timeout(10) do
        booking_thread.value
      end

      expect(booking_result).to eq(:rejected)

      expect(
        Appointment.exists?(
          appointment_slot_id: records[:slot_id]
        )
      ).to be(false)

      expect(
        AvailabilityBlock.find(records[:availability_block_id])
      ).to be_cancelled
    ensure
      release_cancellation << true

      [ cancellation_thread, booking_thread ].compact.each do |thread|
        thread.join(10)
      end
    end
  end
end
