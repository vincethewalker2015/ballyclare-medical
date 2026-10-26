module PatientPortal
  class AppointmentPaymentsController < BaseController
    before_action :set_link
    before_action :set_hold, only: :create

    def create
      result = Payments::TakeHoldPayment.new(hold: @hold).call
      @payment = result.payment
      @client_secret = result.payment_intent.client_secret
      render :confirm
    rescue Payments::CreateForHold::HoldExpired
      redirect_to patient_portal_appointment_hold_path(@hold), alert: "Your reservation has expired."
    rescue Payments::CreateForHold::PaymentInProgress
      redirect_to patient_portal_appointment_hold_path(@hold), alert: "Payment has already been started for this reservation."
    rescue Billing::ConsultationPrice::Unavailable
      redirect_to patient_portal_appointment_hold_path(@hold), alert: "Consultation pricing is currently unavailable."
    rescue Stripe::StripeError
      redirect_to patient_portal_appointment_hold_path(@hold), alert: "Payment could not be started. Please contact the practice if you need assistance."
    end

    def show
      @payment = Payment.where(patient: @link.patient).where(id: params[:id]).first!
      if @payment.appointment.present?
        raise ActiveRecord::RecordNotFound unless @payment.appointment.practice_id == @link.practice_id
      elsif @payment.appointment_hold.present?
        raise ActiveRecord::RecordNotFound unless @payment.appointment_hold.appointment_slot.practice_id == @link.practice_id
      else
        raise ActiveRecord::RecordNotFound
      end
      begin
        Payments::ReconcileStripeStatus.new(payment: @payment).call
      rescue Stripe::StripeError => error
        Rails.logger.warn("Patient payment reconciliation unavailable: #{error.class}")
      end
    end

    private

    def set_link
      @link = current_patient_account.patient_account_links.approved.includes(:patient, :practice).first
      head :forbidden unless @link && @link.patient.practice_id == @link.practice_id
    end

    def set_hold
      @hold = AppointmentHold.joins(:appointment_slot)
        .where(patient: @link.patient, appointment_slots: { practice_id: @link.practice_id })
        .includes(appointment_slot: :clinician).find(params[:appointment_hold_id])
    end
  end
end
