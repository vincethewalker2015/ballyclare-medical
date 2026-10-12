
require "rails_helper"
require "zlib"

RSpec.describe "Payment recovery advisory locking" do
  it "prevents a second PostgreSQL session from acquiring the same lock" do
    lock_key = Zlib.crc32("payment-recovery:concurrency-test")

    first_connection = ActiveRecord::Base.connection

    first_acquired = first_connection.select_value(
      "SELECT pg_try_advisory_lock(#{lock_key})"
    )

    expect(first_acquired).to eq(true)

    # Create an independent connection directly, bypassing
    # Rails' test connection pool and transactional fixtures.
    connection_options =
      first_connection.raw_connection.conninfo_hash.reject do |key, value|
        value.nil? || value == ""
      end

    second_connection = PG.connect(connection_options)

    begin
      second_pid = second_connection.exec(
        "SELECT pg_backend_pid()"
      ).getvalue(0, 0).to_i

      first_pid = first_connection.raw_connection.backend_pid

      expect(second_pid).not_to eq(first_pid)

      second_acquired = second_connection.exec(
        "SELECT pg_try_advisory_lock(#{lock_key})"
      ).getvalue(0, 0)

      expect(second_acquired).to eq("f")
    ensure
      second_connection.close
      first_connection.select_value(
        "SELECT pg_advisory_unlock(#{lock_key})"
      )
    end
  end

  it "holds the advisory lock while calling Stripe" do
    appointment = create(:appointment)

    payment = create(
      :payment,
      appointment: appointment,
      appointment_hold: nil,
      patient: appointment.patient,
      provider: "stripe",
      provider_payment_id: nil,
      status: "pending",
      idempotency_key: SecureRandom.uuid
    )

    lock_key = Zlib.crc32("payment-recovery:#{payment.id}")

    allow(Stripe::PaymentIntent).to receive(:create) do
      primary_connection = ActiveRecord::Base.connection

      connection_options =
        primary_connection.raw_connection.conninfo_hash.reject do |key, value|
          value.nil? || value == ""
        end

      # Bypass Rails' transactional test connection sharing.
      second_connection = PG.connect(connection_options)

      begin
        expect(
          second_connection.backend_pid
        ).not_to eq(primary_connection.raw_connection.backend_pid)

        acquired = second_connection.exec(
          "SELECT pg_try_advisory_lock(#{lock_key})"
        ).getvalue(0, 0)

        expect(acquired).to eq("f")
      ensure
        second_connection.close
      end

      double(
        id: "pi_recovered",
        status: "requires_payment_method"
      )
    end

    result = Payments::RecoverAppointmentPayment.new(
      payment: payment
    ).call

    expect(result.id).to eq("pi_recovered")
    expect(payment.reload.status).to eq("processing")
  end
end
