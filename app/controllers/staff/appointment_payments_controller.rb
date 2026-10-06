module Staff
  class AppointmentPaymentsController < BaseController
    before_action :set_appointment

    def status
      payment = @appointment.payments.find(params[:payment_id])

      if payment.status.in?(%w[pending processing])
        head :no_content
        return
      end

      @balance = Billing::AppointmentBalance.new(
        appointment: @appointment
      ).call

      render turbo_stream: [
        turbo_stream.replace(
          "payment_status",
          partial: "staff/appointment_payments/status",
          locals: {
            appointment: @appointment,
            payment: payment,
            balance: @balance
          }
        ),
        turbo_stream.replace(
          "financial_summary",
          partial: "staff/appointments/financial_summary",
          locals: {
            appointment: @appointment,
            balance: @balance
          }
        )
      ]
    end

    def new
      @balance = appointment_balance
    end

    def create
      amount_cents = amount_to_cents(params[:amount])

      if amount_cents.nil? || amount_cents <= 0
        return render_payment_error(
          "Enter a valid payment amount."
        )
      end

      result = Payments::TakeAppointmentPayment.new(
        appointment: @appointment,
        amount_cents: amount_cents
      ).call

      @payment = result.payment
      @client_secret = result.payment_intent.client_secret

      render :confirm

      rescue Payments::CreateForAppointment::AmountExceedsBalance
        render_payment_error(
          "Payment amount cannot exceed the outstanding balance."
        )

      rescue Payments::CreateForAppointment::PaymentInProgress
        render_payment_error(
          "Another payment is already in progress."
        )

      rescue Stripe::StripeError
        redirect_to practice_appointment_path(@appointment),
                    alert: "The payment could not be started. The appointment has not been affected."
    end

    private

    def set_appointment
      @appointment = current_practice
        .appointments
        .includes(:patient, :payments, :appointment_charges)
        .find(params[:appointment_id])
    end

    def appointment_balance
      Billing::AppointmentBalance.new(
        appointment: @appointment
      ).call
    end

    def render_payment_error(message)
      @balance = appointment_balance
      flash.now[:alert] = message

      render :new, status: :unprocessable_entity
    end

    def amount_to_cents(amount)
      (BigDecimal(amount.to_s) * 100).round.to_i
    rescue ArgumentError
      nil
    end
  end
end
