module PatientPortal
  class AppointmentPaymentsController < BaseController
    before_action :set_hold

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
      @payment = @hold.payments.find(params[:id])
      if @payment.status == "processing" && @payment.provider_payment_id.present?
        begin
          intent = Stripe::PaymentIntent.retrieve(@payment.provider_payment_id)
          Payments::HandleSucceeded.new(payment_intent: intent).call if intent.status == "succeeded"
          @payment.reload
        rescue Stripe::StripeError => error
          Rails.logger.warn("Patient payment reconciliation unavailable: #{error.class}")
        end
      end
    end

    private

    def set_hold
      link = current_patient_account.patient_account_links.approved.includes(:patient, :practice).first
      return head :forbidden unless link && link.patient.practice_id == link.practice_id

      @hold = AppointmentHold.joins(:appointment_slot)
        .where(patient: link.patient, appointment_slots: { practice_id: link.practice_id })
        .includes(appointment_slot: :clinician).find(params[:appointment_hold_id])
    end
  end
end
