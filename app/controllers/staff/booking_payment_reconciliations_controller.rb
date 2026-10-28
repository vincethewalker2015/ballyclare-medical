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

    private

    def require_staff_administrator
      head :forbidden unless current_staff_member.staff_administration_access?
    end
  end
end
