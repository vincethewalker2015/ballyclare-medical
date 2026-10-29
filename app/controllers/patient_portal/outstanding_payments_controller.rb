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

      # Reuse the original Stripe idempotency key after a lost API response.
      pending = @appointment.payments.where(status: "pending", provider_payment_id: nil)
        .order(:created_at).first
      if pending
        return redirect_to patient_portal_outstanding_payment_path(@appointment),
          alert: "Payment verification pending. Please try again shortly." if pending.updated_at > 30.seconds.ago

        intent = PaymentProviders::StripeProvider::CreatePayment.new(payment: pending).call
        if intent.status == "succeeded"
          Payments::HandleSucceeded.new(payment_intent: intent).call
          return redirect_to patient_portal_payment_path(pending)
        end
        if intent.status == "canceled"
          Payments::ReconcileAppointmentPayment.new(payment: pending).call
          return redirect_to patient_portal_outstanding_payment_path(@appointment),
            alert: "The previous payment was cancelled. Please retry."
        end
        unless intent.status.in?(%w[requires_payment_method requires_confirmation requires_action])
          return redirect_to patient_portal_outstanding_payment_path(@appointment),
            alert: "Payment verification pending. Please check back shortly."
        end
        @payment = pending
        @client_secret = intent.client_secret
        return render :confirm
      end

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
