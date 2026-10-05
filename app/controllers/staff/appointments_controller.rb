module Staff
  class AppointmentsController < BaseController
    def index
      @appointments = current_practice
        .appointments
        .includes(:patient, :clinician, :appointment_slot)
        .order(booked_at: :desc)
    end

    def show
      @appointment = current_practice
        .appointments
        .includes(
          :patient,
          :clinician,
          :appointment_slot,
          :appointment_charges,
          :payments
        )
        .find(params[:id])

      @balance = Billing::AppointmentBalance.new(
        appointment: @appointment
      ).call

      @returned_payment =
        @appointment.payments.find_by(id: params[:payment_return]) if params[:payment_return].present?
    end

    def new
      load_booking_options
    end

    def create
      if params[:patient_id].blank? ||
         params[:appointment_slot_id].blank?
        return render_booking_error(
          "Select a patient, clinician and available appointment."
        )
      end

      if params[:charge_amount].blank?
        return render_booking_error(
          "Enter a consultation charge."
        )
      end

      amount_cents = amount_to_cents(params[:charge_amount])

      if amount_cents.nil?
        return render_booking_error(
          "Enter a valid consultation charge."
        )
      end

      patient = current_practice
        .patients
        .find(params[:patient_id])

      appointment_slot = current_practice
        .appointment_slots
        .find(params[:appointment_slot_id])

      appointment = Booking::CreateStaffAppointment.new(
        appointment_slot: appointment_slot,
        patient: patient,
        booked_by: current_user,
        amount_cents: amount_cents,
        reason: params[:reason].presence
      ).call

      redirect_to practice_appointment_path(appointment),
                  notice: "Appointment booked successfully."
    rescue Booking::CreateStaffAppointment::SlotUnavailable
      render_booking_error(
        "That appointment is no longer available. Please choose another time."
      )
    end

    def available_slots
      now = Time.current

      @clinician = current_practice
        .staff_members
        .where(staff_type: %w[doctor nurse])
        .find(params[:clinician_id])

      @appointment_slots = current_practice
        .appointment_slots
        .where(clinician: @clinician)
        .where("appointment_slots.starts_at >= ?", now)
        .where.missing(:appointment)
        .where.not(
          id: AppointmentHold
            .where("expires_at > ?", now)
            .select(:appointment_slot_id)
        )
        .order(:starts_at)
        .limit(20)

      render turbo_stream: turbo_stream.replace(
        "available_appointment_slots",
        partial: "staff/appointments/available_slots",
        locals: {
          appointment_slots: @appointment_slots,
          practice_timezone: current_practice.timezone
        }
      )
    end

    private

      def load_booking_options
        @patients = current_practice
          .patients
          .order(:last_name, :first_name)

        @clinicians = current_practice
          .staff_members
          .where(staff_type: %w[doctor nurse])
          .order(:last_name, :first_name)
      end

    def render_booking_error(message)
      load_booking_options

      flash.now[:alert] = message

      render :new, status: :unprocessable_entity
    end

    def amount_to_cents(amount)
      cents = (BigDecimal(amount.to_s) * 100).round.to_i

      return nil if cents.negative?

      cents
    rescue ArgumentError
      nil
    end
  end
end
