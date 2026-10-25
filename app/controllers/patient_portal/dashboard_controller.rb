module PatientPortal
  class DashboardController < BaseController
    def show
      @dashboard = PatientPortal::Dashboard.new(patient_account: current_patient_account).call
    end
  end
end
