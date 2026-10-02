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
    end

    def create
    end
  end
end
