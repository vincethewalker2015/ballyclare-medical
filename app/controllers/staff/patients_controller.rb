module Staff
  class PatientsController < BaseController
    def index
      @patients = current_practice.patients.order(:last_name, :first_name)
    end
  end
end
