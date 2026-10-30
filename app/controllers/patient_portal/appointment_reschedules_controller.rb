module PatientPortal
  class AppointmentReschedulesController < BaseController
    before_action :load_appointment

    def edit
      return unless @appointment
      unless @appointment.status.in?(%w[booked confirmed]) && @appointment.appointment_slot.starts_at >= 24.hours.from_now
        return redirect_to patient_portal_appointment_history_path, alert: "Rescheduling requires at least 24 hours notice and an upcoming booked or confirmed appointment."
      end
      @slots = available_slots
    end

    def update
      return unless @appointment
      replacement_slot = @appointment.practice.appointment_slots.find(params.require(:appointment_slot_id))
      Appointments::Reschedule.new(appointment: @appointment,
        replacement_slot: replacement_slot, patient_account: current_patient_account).call
      redirect_to patient_portal_appointment_history_path, notice: "Appointment rescheduled."
    rescue Appointments::Reschedule::NotAllowed => error
      redirect_to edit_patient_portal_appointment_reschedule_path(@appointment), alert: error.message
    end

    private

    def load_appointment
      patient_account_link = current_patient_account.patient_account_links.approved.includes(:patient, :practice).first
      return render_access_unavailable unless patient_account_link &&
        patient_account_link.patient.practice_id == patient_account_link.practice_id

      @appointment = patient_account_link.practice.appointments
        .where(patient_id: patient_account_link.patient_id)
        .includes(:appointment_slot, :clinician).find(params[:appointment_id])
    end

    def available_slots
      @appointment.practice.staff_members.where(staff_type: @appointment.clinician.staff_type, active: true)
        .flat_map do |clinician|
          Appointments::AvailableSlots.new(practice: @appointment.practice,
            clinician: clinician, online_only: true, limit: 50).call.to_a
        end.sort_by(&:starts_at).first(100)
    end
  end
end
