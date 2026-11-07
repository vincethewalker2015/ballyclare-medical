module Payments
  # Advisory monitoring only. This service never changes payment status or
  # activates the emergency unpaid-booking policy.
  class StripeOutageMonitor
    WINDOW = 5.minutes
    MIN_DISTINCT_PAYMENTS = 3
    ALERT_COOLDOWN = 30.minutes
    FAILURE_ACTION = "stripe_outage.api_failure"
    SUSPECTED_ACTION = "stripe_outage.suspected"

    def self.record_failure(payment:, error:, source:)
      return unless payment&.provider == "stripe"
      return unless error.is_a?(Stripe::APIConnectionError) || error.is_a?(Stripe::APIError)

      practice = payment.appointment&.practice ||
        payment.appointment_hold&.appointment_slot&.practice ||
        payment.guest_booking&.practice
      return unless practice

      suspected = false
      practice.with_lock do
        events = AuditEvent.where(practice: practice, auditable: practice,
          action: FAILURE_ACTION).where("created_at > ?", WINDOW.ago)

        # Repeated polls against one unresolved payment are only one signal.
        unless events.where("metadata ->> 'payment_id' = ?", payment.id.to_s).exists?
          AuditEvent.create!(
            practice: practice, auditable: practice, action: FAILURE_ACTION,
            metadata: { payment_id: payment.id, source: source, error_class: error.class.name }
          )
        end

        affected_payments = events.distinct.pluck(Arel.sql("metadata ->> 'payment_id'"))
        recent_alert = AuditEvent.where(practice: practice, auditable: practice,
          action: SUSPECTED_ACTION).where("created_at > ?", ALERT_COOLDOWN.ago).exists?

        if affected_payments.size >= MIN_DISTINCT_PAYMENTS && !recent_alert &&
            !StripeOutageDeclaration.active?(practice: practice)
          AuditEvent.create!(
            practice: practice, auditable: practice, action: SUSPECTED_ACTION,
            metadata: { distinct_payments: affected_payments.size,
                        window_minutes: WINDOW.in_minutes }
          )
          suspected = true
        end
      end

      StripeOutageAlertMailer.suspected(practice: practice).deliver_later if suspected
      suspected
    rescue StandardError => monitor_error
      # Monitoring must never mask Stripe's original failure.
      Rails.logger.error("Stripe outage monitoring unavailable: #{monitor_error.class}")
      false
    end

    def self.suspected_event(practice:)
      AuditEvent.where(practice: practice, auditable: practice,
        action: SUSPECTED_ACTION).where("created_at > ?", ALERT_COOLDOWN.ago)
        .order(created_at: :desc).first
    end
  end
end
