module Staff
  class AppointmentsController < BaseController
    def index
      @diary_view = params[:view].presence_in(%w[today upcoming past]) || "today"

      Time.use_zone(current_practice.timezone) do
        today_start = Time.zone.now.beginning_of_day
        tomorrow_start = today_start + 1.day

        appointments = current_practice
          .appointments
          .includes(:patient, :clinician, :appointment_slot)
          .joins(:appointment_slot)

        @appointments =
          case @diary_view
          when "upcoming"
            appointments
              .where("appointment_slots.starts_at >= ?", tomorrow_start)
              .order("appointment_slots.starts_at ASC")
          when "past"
            appointments
              .where("appointment_slots.starts_at < ?", today_start)
              .order("appointment_slots.starts_at DESC")
          else
            appointments
              .where(
                appointment_slots: {
                  starts_at: today_start...tomorrow_start
                }
              )
              .order("appointment_slots.starts_at ASC")
          end
      end

      @appointment_balances = Billing::AppointmentBalances.new(
        appointments: @appointments
      ).call
    end

    def show
      @appointment = current_practice
        .appointments
        .includes(
          :patient,
          :clinician,
          :appointment_slot,
          :appointment_charges,
          :payments,
          appointment_status_changes: :changed_by
        )
        .find(params[:id])

      @balance = Billing::AppointmentBalance.new(
        appointment: @appointment
      ).call

      @allowed_status_transitions =
        Appointments::ChangeStatus.allowed_transitions(
          @appointment.status
        )

      @status_changes =
        @appointment.appointment_status_changes.order(created_at: :desc)

      @returned_payment =
        @appointment.payments.find_by(
          id: params[:payment_return]
        ) if params[:payment_return].present?
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
        .joins(:availability_block)
        .merge(AvailabilityBlock.active)
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

    def status
      appointment = current_practice.appointments.find(params[:id])

      Appointments::ChangeStatus.new(
        appointment: appointment,
        to_status: params[:status],
        changed_by: current_user
      ).call

      allowed_status_transitions =
        Appointments::ChangeStatus.allowed_transitions(
          appointment.status
        )

      status_changes =
        appointment.appointment_status_changes
          .includes(:changed_by)
          .order(created_at: :desc)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              "appointment_status_badge",
              partial: "staff/appointments/status_badge",
              locals: {
                appointment: appointment
              }
            ),
            turbo_stream.replace(
              "appointment_lifecycle_controls",
              partial: "staff/appointments/lifecycle_controls",
              locals: {
                appointment: appointment,
                allowed_status_transitions: allowed_status_transitions
              }
            ),
            turbo_stream.replace(
              "appointment_activity",
              partial: "staff/appointments/activity",
              locals: {
                appointment: appointment,
                status_changes: status_changes
              }
            )
          ]
        end

        format.html do
          redirect_to practice_appointment_path(appointment),
                      notice: "Appointment status updated."
        end
      end
    rescue Appointments::ChangeStatus::InvalidTransition => error
      redirect_to practice_appointment_path(appointment),
                  alert: error.message
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

      render :new, status: :unprocessable_content
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
