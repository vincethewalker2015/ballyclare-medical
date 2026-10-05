module Staff
  class AppointmentPaymentsController < BaseController
    before_action :set_appointment

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

      payment = Payments::TakeAppointmentPayment.new(
        appointment: @appointment,
        amount_cents: amount_cents
      ).call

      redirect_to practice_appointment_path(@appointment),
                  notice: payment_notice(payment)

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

    def payment_notice(payment)
      case payment.status
      when "succeeded"
        "Payment received successfully."
      when "processing"
        "Payment is being processed."
      else
        "Payment started."
      end
    end
  end
end
