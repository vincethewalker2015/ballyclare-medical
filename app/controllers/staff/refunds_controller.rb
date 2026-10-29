module Staff
  class RefundsController < BaseController
    before_action :require_staff_administrator

    def index
      practice_payment_ids = Payment.where(
        patient_id: current_practice.patients.select(:id)
      ).or(
        Payment.where(guest_booking_id: GuestBooking.where(practice_id: current_practice.id).select(:id))
      ).or(
        Payment.where(appointment_id: current_practice.appointments.select(:id))
      )

      @refunds = Refund
        .where(payment_id: practice_payment_ids.select(:id))
        .includes(payment: [ :patient, :guest_booking, :appointment ])
        .order(created_at: :desc, id: :desc)
        .limit(100)

      Payments::ReconcileProcessingRefunds.new(refunds: @refunds).call
      @refunds.each(&:reload)
    end

    private

    def require_staff_administrator
      head :forbidden unless current_staff_member.staff_administration_access?
    end
  end
end
