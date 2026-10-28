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
        .order(updated_at: :asc, id: :asc)
        .limit(100)
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
          payment.appointment_id.present? || !intent_id.match?(/\\Api_[a-zA-Z0-9_]+\\z/)
        redirect_to practice_booking_payment_reconciliations_path,
          alert: "Payment is not eligible for verification."
        return
      end

      intent = Stripe::PaymentIntent.retrieve(intent_id)
      if intent.metadata&.[]("payment_id").to_s != payment.id.to_s ||
          (payment.provider_payment_id.present? && payment.provider_payment_id != intent.id)
        redirect_to practice_booking_payment_reconciliations_path,
          alert: "Stripe PaymentIntent does not match this payment."
        return
      end

      redirect_to practice_booking_payment_reconciliations_path,
        notice: "Stripe reference verified. No payment changes were made."
    rescue Stripe::StripeError
      redirect_to practice_booking_payment_reconciliations_path,
        alert: "Stripe verification is unavailable. No payment changes were made."
    end

    private

    def require_staff_administrator
      head :forbidden unless current_staff_member.staff_administration_access?
    end
  end
end
