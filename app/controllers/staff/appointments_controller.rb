module Staff
  class AppointmentsController < BaseController
    def index
      @appointments = current_practice
        .appointments
        .includes(:patient, :clinician, :appointment_slot)
        .order(booked_at: :desc)
    end

    def show
    end

    def new
      @patients = current_practice
        .patients
        .order(:last_name, :first_name)

      @clinicians = current_practice
        .staff_members
        .where(staff_type: %w[doctor nurse])
        .includes(:user)
        .order(:last_name, :first_name)
    end

    def create
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
        locals: { appointment_slots: @appointment_slots }
      )
    end
  end
end
