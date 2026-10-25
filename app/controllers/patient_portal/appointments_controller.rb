module PatientPortal
  class AppointmentsController < BaseController
    def index
      @discovery = PatientPortal::AppointmentDiscovery.new(
        patient_account: current_patient_account,
        clinician_id: params[:clinician_id],
        date: params[:date]
      ).call
      head :forbidden unless @discovery.patient
    end
  end
end
