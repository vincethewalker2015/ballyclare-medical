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
  end
end
