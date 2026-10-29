module PatientPortal
  class OutstandingPaymentsController < BaseController
    before_action :set_link
    before_action :set_appointment

    def show
      @balance = Billing::AppointmentBalance.new(appointment: @appointment).call
      @in_progress = @appointment.payments.where(status: %w[pending processing]).exists?
    end

    def create
      if Payments::StripeOutageDeclaration.active?(practice: @link.practice)
        return redirect_to patient_portal_outstanding_payment_path(@appointment),
          alert: "Secure payment is temporarily unavailable."
      end

      # The existing appointment payment service locks the appointment, checks
      # the outstanding balance and refuses concurrent in-progress payments.
      balance = Billing::AppointmentBalance.new(appointment: @appointment).call
      return redirect_to patient_portal_outstanding_payment_path(@appointment),
        alert: "There is no outstanding balance." unless balance[:balance_cents].positive?

      result = Payments::TakeAppointmentPayment.new(
        appointment: @appointment, amount_cents: balance[:balance_cents]
      ).call
      @payment = result.payment
      @client_secret = result.payment_intent.client_secret
      render :confirm
    rescue Payments::CreateForAppointment::AmountExceedsBalance,
           Payments::CreateForAppointment::PaymentInProgress,
           Payments::CreateForAppointment::AppointmentCancelled
      redirect_to patient_portal_outstanding_payment_path(@appointment),
        alert: "Payment cannot be started. Please refresh the balance or wait for an existing payment to be reconciled."
    rescue Stripe::StripeError
      redirect_to patient_portal_outstanding_payment_path(@appointment),
        alert: "Payment could not be started. Please contact the practice if the problem persists."
    end

    private

    def set_link
      @link = current_patient_account.patient_account_links.approved
        .includes(:patient, :practice).first
      render_access_unavailable unless @link && @link.patient.practice_id == @link.practice_id
    end

    def set_appointment
      @appointment = @link.practice.appointments
        .where(patient_id: @link.patient_id).includes(:appointment_slot).find(params[:appointment_id])
    end
  end
end
