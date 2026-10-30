module PatientPortal
  class AppointmentCancellationsController < BaseController
    def update
      link = current_patient_account.patient_account_links.approved
        .includes(:patient, :practice).first
      return render_access_unavailable unless link && link.patient.practice_id == link.practice_id

      appointment = link.practice.appointments.where(patient_id: link.patient_id)
        .includes(:appointment_slot).find(params[:appointment_id])

      Appointments::ChangeStatus.new(
        appointment: appointment, to_status: "cancelled",
        changed_by: nil, patient_account: current_patient_account
      ).call

      redirect_to patient_portal_appointment_history_path,
        notice: "Appointment cancelled. Any eligible refund has been requested."
    rescue Appointments::ChangeStatus::InvalidTransition,
           Appointments::ChangeStatus::PaymentInProgress => error
      redirect_to patient_portal_appointment_history_path, alert: error.message
    end
  end
end
