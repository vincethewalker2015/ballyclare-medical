module PatientPortal
  class DashboardController < BaseController
    def show
      @revoked_access = current_patient_account.patient_account_links.where(status: "revoked").exists?
      @dashboard = PatientPortal::Dashboard.new(patient_account: current_patient_account).call
    end
  end
end
