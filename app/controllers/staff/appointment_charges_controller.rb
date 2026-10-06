module Staff
  class AppointmentChargesController < BaseController
    before_action :set_appointment

    def new
    end

    def create
      amount_cents = amount_to_cents(params[:amount])

      if params[:description].blank?
        return render_charge_error("Enter a description.")
      end

      if amount_cents.nil? || amount_cents <= 0
        return render_charge_error("Enter a valid charge amount.")
      end

      Billing::CreateCharge.new(
        appointment: @appointment,
        description: params[:description],
        charge_type: "additional",
        amount_cents: amount_cents,
        created_by: current_user
      ).call

      redirect_to practice_appointment_path(@appointment),
                  notice: "Charge added."
    end

    private

    def set_appointment
      @appointment = current_practice
        .appointments
        .includes(
          :patient,
          :appointment_charges,
          :payments
        )
        .find(params[:appointment_id])
    end

    def render_charge_error(message)
      @error = message

      render :new,
             status: :unprocessable_content
    end

    def amount_to_cents(value)
      return if value.blank?

      (BigDecimal(value.to_s) * 100).round.to_i
    rescue ArgumentError
      nil
    end
  end
end
