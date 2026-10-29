module PatientPortal
  class PaymentHistoryController < BaseController
    before_action :set_link

    def index
      @patient = @link.patient
      @practice = @link.practice
      @payments = scoped_payments.includes(:refunds, appointment: :appointment_slot,
        appointment_hold: :appointment_slot).order(created_at: :desc, id: :desc)
    end

    def show
      @practice = @link.practice
      @payment = scoped_payments.includes(:refunds, appointment: :appointment_slot,
        appointment_hold: :appointment_slot).find(params[:id])
      return head :not_found unless @payment.status == "succeeded"

      @successful_refunds = @payment.refunds.select { |refund| refund.status == "succeeded" }
    end

    private

    def set_link
      @link = current_patient_account.patient_account_links.approved
        .includes(:patient, :practice).first
      render_access_unavailable unless @link && @link.patient.practice_id == @link.practice_id
    end

    def scoped_payments
      Payment.where(patient_id: @link.patient_id)
        .where(
          "payments.appointment_id IN (SELECT id FROM appointments WHERE practice_id = :practice AND patient_id = :patient) OR " \
          "payments.appointment_hold_id IN (SELECT appointment_holds.id FROM appointment_holds " \
          "INNER JOIN appointment_slots ON appointment_slots.id = appointment_holds.appointment_slot_id " \
          "WHERE appointment_slots.practice_id = :practice AND appointment_holds.patient_id = :patient)",
          practice: @link.practice_id, patient: @link.patient_id
        )
    end
  end
end
