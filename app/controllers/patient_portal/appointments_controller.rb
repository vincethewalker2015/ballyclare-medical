module PatientPortal
  class AppointmentsController < BaseController
    def index
      @discovery = PatientPortal::AppointmentDiscovery.new(
        patient_account: current_patient_account,
        clinician_id: params[:clinician_id],
        date: params[:date]
      ).call
      return head :forbidden unless @discovery.patient

      @consultation_fee = if @discovery.clinician
        @discovery.practice.consultation_fees.find_by(clinician_type: @discovery.clinician.staff_type)
      end
    end
  end
end
