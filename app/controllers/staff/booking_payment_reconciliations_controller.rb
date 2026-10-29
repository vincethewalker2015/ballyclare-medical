module Staff
  class BookingPaymentReconciliationsController < BaseController
    before_action :require_staff_administrator

    def index
      practice_payment_ids = Payment.where(
        patient_id: current_practice.patients.select(:id)
      ).or(
        Payment.where(
          guest_booking_id: GuestBooking.where(practice_id: current_practice.id).select(:id)
        )
      )

      @payments = Payment
        .where(id: practice_payment_ids.select(:id))
        .where(appointment_id: nil, provider: "stripe", status: %w[pending processing])
        .where("payments.updated_at <= ?", 15.minutes.ago)
        .includes(:patient, :guest_booking)
        .order(updated_at: :asc, id: :asc)
        .limit(100)

      @stripe_verifications = AuditEvent
        .where(practice: current_practice, auditable_type: "Payment",
          auditable_id: @payments.map(&:id),
          action: %w[stripe_payment.verification_matched stripe_payment.verification_unavailable])
        .order(created_at: :desc, id: :desc)
        .each_with_object({}) do |event, latest|
          latest[event.auditable_id] ||= event
        end
    end


    def cancel
      payment = Payment.where(
        patient_id: current_practice.patients.select(:id)
      ).or(
        Payment.where(
          guest_booking_id: GuestBooking.where(practice_id: current_practice.id).select(:id)
        )
      ).find(params[:id])

      intent_id = params[:payment_intent_id].to_s.strip
      unless payment.provider == "stripe" && payment.status.in?(%w[pending processing]) &&
          payment.appointment_id.nil? && payment.provider_payment_id == intent_id &&
          intent_id.match?(/\Api_[a-zA-Z0-9_]+\z/)
        return redirect_to practice_booking_payment_reconciliations_path,
          alert: "Payment is not eligible for cancellation."
      end

      intent = Stripe::PaymentIntent.retrieve(intent_id)
      unless intent.metadata&.[]("payment_id").to_s == payment.id.to_s &&
          intent.amount == payment.amount_cents &&
          intent.currency.casecmp?(payment.currency) &&
          intent.status == "requires_payment_method"
        return redirect_to practice_booking_payment_reconciliations_path,
          alert: "Stripe payment could not be safely cancelled. No changes were made."
      end

      cancelled_intent = Stripe::PaymentIntent.cancel(intent_id)
      unless cancelled_intent.id == intent_id && cancelled_intent.status == "canceled" &&
          cancelled_intent.metadata&.[]("payment_id").to_s == payment.id.to_s &&
          cancelled_intent.amount == payment.amount_cents &&
          cancelled_intent.currency.casecmp?(payment.currency)
        return redirect_to practice_booking_payment_reconciliations_path,
          alert: "Stripe cancellation was not confirmed. Manual review required."
      end

      begin
        Payments::HandleFailed.new(payment_intent: cancelled_intent).call
      rescue ActiveRecord::ActiveRecordError => error
        AuditEvent.create!(
          practice: current_practice,
          user: current_user,
          auditable: payment,
          action: "stripe_payment.cancellation_reconciliation_failed",
          metadata: { payment_intent_id: intent_id, error_class: error.class.name }
        )
        return redirect_to practice_booking_payment_reconciliations_path,
          alert: "Stripe cancellation confirmed, but local reconciliation failed. Manual review required."
      end

      unless payment.reload.status == "failed"
        return redirect_to practice_booking_payment_reconciliations_path,
          alert: "Payment was not closed as abandoned. Review the current payment outcome."
      end

      AuditEvent.create!(
        practice: current_practice,
        user: current_user,
        auditable: payment,
        action: "stripe_payment.abandoned_cancelled",
        metadata: { payment_intent_id: intent_id, payment_status: payment.reload.status }
      )
      redirect_to practice_booking_payment_reconciliations_path,
        notice: "Stripe PaymentIntent cancelled and payment outcome reconciled."
    rescue Stripe::StripeError => error
      Rails.logger.warn("Stripe payment cancellation unavailable: #{error.class}")
      redirect_to practice_booking_payment_reconciliations_path,
        alert: "Stripe cancellation could not be confirmed. Payment requires review."
    end

    def verify
      payment = Payment.where(
        patient_id: current_practice.patients.select(:id)
      ).or(
        Payment.where(
          guest_booking_id: GuestBooking.where(practice_id: current_practice.id).select(:id)
        )
      ).find(params[:id])

      intent_id = params[:payment_intent_id].to_s.strip
      if payment.provider != "stripe" || !payment.status.in?(%w[pending processing]) ||
          payment.appointment_id.present? || !intent_id.match?(/\Api_[a-zA-Z0-9_]+\z/)
        redirect_to practice_booking_payment_reconciliations_path,
          alert: "Payment is not eligible for verification."
        return
      end

      intent = Stripe::PaymentIntent.retrieve(intent_id)
      if intent.metadata&.[]("payment_id").to_s != payment.id.to_s ||
          (payment.provider_payment_id.present? && payment.provider_payment_id != intent.id)
        AuditEvent.create!(
          practice: current_practice,
          user: current_user,
          auditable: payment,
          action: "stripe_payment.verification_rejected",
          metadata: {
            payment_intent_id: intent.id,
            reason: "payment_reference_mismatch"
          }
        )
        redirect_to practice_booking_payment_reconciliations_path,
          alert: "Stripe PaymentIntent does not match this payment."
        return
      end

      AuditEvent.create!(
        practice: current_practice,
        user: current_user,
        auditable: payment,
        action: "stripe_payment.verification_matched",
        metadata: {
          payment_intent_id: intent.id,
          stripe_status: intent.status
        }
      )

      if intent.status == "succeeded"
        Payments::HandleSucceeded.new(payment_intent: intent).call
        AuditEvent.create!(
          practice: current_practice,
          user: current_user,
          auditable: payment,
          action: "stripe_payment.recovered",
          metadata: {
            payment_intent_id: intent.id,
            payment_status: payment.reload.status
          }
        )
        redirect_to practice_booking_payment_reconciliations_path,
          notice: "Stripe payment recovered and booking outcome reconciled."
      else
        redirect_to practice_booking_payment_reconciliations_path,
          notice: "Stripe reference verified. No payment changes were made."
      end
    rescue Payments::HandleSucceeded::AmountMismatch,
           Payments::HandleSucceeded::CurrencyMismatch => error
      AuditEvent.create!(
        practice: current_practice,
        user: current_user,
        auditable: payment,
        action: "stripe_payment.verification_rejected",
        metadata: {
          payment_intent_id: intent_id,
          reason: error.class.name
        }
      )
      redirect_to practice_booking_payment_reconciliations_path,
        alert: "Stripe payment amount or currency does not match. No booking or payment changes were made."
    rescue Stripe::StripeError => error
      AuditEvent.create!(
        practice: current_practice,
        user: current_user,
        auditable: payment,
        action: "stripe_payment.verification_unavailable",
        metadata: {
          payment_intent_id: intent_id,
          error_class: error.class.name
        }
      )
      redirect_to practice_booking_payment_reconciliations_path,
        alert: "Stripe verification is unavailable. No payment changes were made."
    end

    private

    def require_staff_administrator
      head :forbidden unless current_staff_member.staff_administration_access?
    end
  end
end
