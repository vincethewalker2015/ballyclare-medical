module Appointments
  class ChangeStatus
    class InvalidTransition < StandardError; end
    class PaymentInProgress < StandardError; end

    TRANSITIONS = {
      "booked" => %w[confirmed cancelled],
      "confirmed" => %w[arrived cancelled did_not_attend],
      "arrived" => %w[in_consultation cancelled],
      "in_consultation" => %w[completed referred],
      "completed" => [],
      "cancelled" => [],
      "referred" => [],
      "did_not_attend" => []
    }.freeze

    def self.allowed_transitions(status)
      TRANSITIONS.fetch(status.to_s, [])
    end

    def initialize(appointment:, to_status:, changed_by:, patient_account: nil)
      @appointment = appointment
      @to_status = to_status.to_s
      @changed_by = changed_by
      @patient_account = patient_account
    end

    def call
      appointment.with_lock do
        validate_transition!
        validate_patient_cancellation!
        ensure_no_payment_in_progress!

        from_status = appointment.status

        Appointment.transaction do
          appointment.update!(status: to_status)

          appointment.appointment_status_changes.create!(
            from_status: from_status,
            to_status: to_status,
            changed_by: changed_by,
            notes: @patient_account ? "Cancelled by patient account #{@patient_account.id}" : nil
          )

          if to_status == "cancelled"
            appointment.appointment_charges
                       .active
                       .update_all(status: "voided")

            successful_payments =
              appointment.payments.where(status: "succeeded")

            if successful_payments.exists?
              successful_payments.each do |payment|
                already_refunded_cents = payment.refunds
                  .where(status: %w[pending processing succeeded])
                  .sum(:amount_cents)

                remaining_cents = payment.amount_cents - already_refunded_cents

                next if remaining_cents <= 0

                refund = Payments::CreateRefund.new(
                  payment: payment,
                  amount_cents: remaining_cents,
                  requested_by: changed_by,
                  reason: @patient_account ? "Patient cancelled appointment" : "Clinic cancelled appointment"
                ).call

                ActiveRecord.after_all_transactions_commit do
                  begin
                    ProcessRefundJob.perform_later(refund.id)
                  rescue StandardError => error
                    Rails.logger.error(
                      "Failed to enqueue refund processing " \
                      "for refund #{refund.id}: " \
                      "#{error.class}: #{error.message}"
                    )
                  end
                end
              end
            end
          end
        end
      end

      appointment
    end

    private

    attr_reader :appointment, :to_status, :changed_by

    def validate_transition!
      allowed = TRANSITIONS.fetch(appointment.status, [])

      return if allowed.include?(to_status)

      raise InvalidTransition,
            "Cannot change appointment from #{appointment.status} to #{to_status}"
    end

    def validate_patient_cancellation!
      return unless @patient_account

      raise InvalidTransition, "Patients may only cancel appointments" unless to_status == "cancelled"
      raise InvalidTransition, "Patients may only cancel booked or confirmed appointments" unless %w[booked confirmed].include?(appointment.status)

      approved = @patient_account.patient_account_links.approved.exists?(\n        patient_id: appointment.patient_id, practice_id: appointment.practice_id\n      )\n      raise InvalidTransition, "Patient access is not approved for this appointment" unless approved\n\n      starts_at = appointment.appointment_slot.starts_at
      raise InvalidTransition, "Cancellation requires at least 24 hours notice" if starts_at < 24.hours.from_now
    end

    def ensure_no_payment_in_progress!
      return unless to_status == "cancelled"

      if appointment.payments.where(status: %w[pending processing]).exists?
        raise PaymentInProgress,
              "Cannot cancel an appointment while a payment is in progress."
      end
    end
  end
end
