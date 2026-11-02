module Staff
  class ConsultationsController < BaseController
    def show
      # A consultation is a clinician-only record, regardless of administrative role.
      return head :forbidden unless current_staff_member.access_level == "staff_clinician" &&
        current_staff_member.staff_type.in?(%w[doctor nurse])

      @appointment = current_practice.appointments
        .includes(:patient, :clinician, :appointment_slot, :encounter)
        .find(params[:appointment_id])

      return head :forbidden unless @appointment.clinician_id == current_staff_member.id

      # Previous notes remain inside this practice; neither administration nor
      # patient-portal endpoints inherit this clinical-record permission.
      @previous_encounters = current_practice.encounters
        .where(patient_id: @appointment.patient_id)
        .where.not(appointment_id: @appointment.id)
        .includes(:clinician, clinical_notes: :author)
        .order(started_at: :desc, created_at: :desc)

      AuditEvent.create!(
        practice: current_practice,
        user: current_user,
        auditable: @appointment,
        action: "clinical.consultation_viewed",
        metadata: { staff_member_id: current_staff_member.id }
      )
    end
  end
end
