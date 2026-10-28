module PatientPortal
  class EmergencyBookingsController < BaseController
    before_action :set_link

    def create
      hold = AppointmentHold.joins(:appointment_slot)
        .where(patient: @link.patient, appointment_slots: { practice_id: @link.practice_id })
        .find(params[:appointment_hold_id])

      appointment = PatientPortal::CompleteEmergencyUnpaidBooking.new(hold: hold).call
      redirect_to patient_portal_emergency_booking_path(appointment)
    rescue PatientPortal::CompleteEmergencyUnpaidBooking::Unavailable,
           Billing::ConsultationPrice::Unavailable
      redirect_to patient_portal_appointment_hold_path(params[:appointment_hold_id]),
        alert: "Emergency booking is unavailable. Please contact the practice."
    end

    def show
      @appointment = Appointment.where(
        patient: @link.patient, practice_id: @link.practice_id, id: params[:id]
      ).find_by!(status: "booked")
      @charge = @appointment.appointment_charges.active.first!
    end

    private

    def set_link
      @link = current_patient_account.patient_account_links.approved.includes(:patient, :practice).first
      head :forbidden unless @link && @link.patient.practice_id == @link.practice_id
    end
  end
end
