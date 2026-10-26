module PatientPortal
  class AppointmentHoldsController < BaseController
    def create
      @hold = PatientPortal::ReserveAppointment.new(
        patient_account: current_patient_account,
        appointment_slot_id: params.require(:appointment_slot_id)
      ).call

      redirect_to patient_portal_appointment_hold_path(@hold),
                  notice: "Your selected time is held temporarily."
    rescue PatientPortal::ReserveAppointment::NotApproved
      head :forbidden
    rescue ActiveRecord::RecordNotFound, PatientPortal::ReserveAppointment::NotOnlineBookable,
           AppointmentSlot::Unavailable, AppointmentSlot::PracticeMismatch
      redirect_to patient_portal_appointments_path,
                  alert: "That appointment is no longer available. Please choose another time."
    end

    def show
      link = current_patient_account.patient_account_links.approved.includes(:patient, :practice).first
      return head :forbidden unless link && link.patient.practice_id == link.practice_id

      @hold = AppointmentHold.joins(:appointment_slot)
        .where(patient: link.patient, appointment_slots: { practice_id: link.practice_id })
        .includes(appointment_slot: :clinician).find(params[:id])
    end
  end
end
