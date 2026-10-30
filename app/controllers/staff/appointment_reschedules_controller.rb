module Staff
  class AppointmentReschedulesController < BaseController
    before_action :require_operational_access

    def edit
      @appointment = scoped_appointment
      unless @appointment.status.in?(%w[booked confirmed]) && @appointment.appointment_slot.starts_at.future?
        return redirect_to practice_appointment_path(@appointment), alert: "This appointment cannot be rescheduled."
      end
      @slots = @appointment.practice.staff_members
        .where(staff_type: @appointment.clinician.staff_type, active: true).flat_map do |clinician|
          Appointments::AvailableStaffSlots.new(practice: current_practice,
            clinician: clinician).call.limit(50).to_a
        end.sort_by(&:starts_at).first(100)
    end

    def update
      appointment = scoped_appointment
      replacement_slot = current_practice.appointment_slots.find(params.require(:appointment_slot_id))
      Appointments::Reschedule.new(appointment: appointment,
        replacement_slot: replacement_slot, staff_user: current_user).call
      redirect_to practice_appointment_path(appointment), notice: "Appointment rescheduled."
    rescue Appointments::Reschedule::NotAllowed => error
      redirect_to edit_practice_appointment_reschedule_path(appointment), alert: error.message
    end

    private

    def scoped_appointment
      scope = current_practice.appointments.includes(:appointment_slot, :clinician)
      scope = scope.where(clinician_id: current_staff_member.id) if current_staff_member.access_level == "staff_clinician"
      scope.find(params[:appointment_id])
    end
  end
end
