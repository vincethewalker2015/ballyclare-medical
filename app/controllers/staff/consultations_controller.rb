module Staff
  class ConsultationsController < BaseController
    before_action :load_authorized_appointment

    def show
      @draft = @appointment.encounter&.clinical_notes&.find_by(note_type: "consultation", status: "draft")
      # Previous notes remain inside this practice; neither administration nor
      # patient-portal endpoints inherit this clinical-record permission.
      @previous_encounters = current_practice.encounters
        .where(patient_id: @appointment.patient_id)
        .where("appointment_id IS NULL OR appointment_id <> ?", @appointment.id)
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

    def create
      Consultations::Start.new(
        appointment: @appointment,
        clinician: current_staff_member,
        user: current_user
      ).call

      redirect_to practice_appointment_consultation_path(@appointment),
                  notice: "Consultation started."
    rescue Consultations::Start::InvalidState => error
      redirect_to practice_appointment_consultation_path(@appointment), alert: error.message
    end

    def draft
      Consultations::SaveDraft.new(
        appointment: @appointment, clinician: current_staff_member, user: current_user,
        body: params.require(:clinical_note).fetch(:body),
        lock_version: params.require(:clinical_note).fetch(:lock_version)
      ).call
      redirect_to practice_appointment_consultation_path(@appointment), notice: "Draft saved."
    rescue Consultations::SaveDraft::Conflict
      redirect_to practice_appointment_consultation_path(@appointment), alert: "Draft changed elsewhere. Reload and review before saving again."
    rescue Consultations::SaveDraft::InvalidState
      redirect_to practice_appointment_consultation_path(@appointment), alert: "This consultation is not open for editing."
    end

    private

    def load_authorized_appointment
      return head :forbidden unless current_staff_member.access_level == "staff_clinician" &&
        current_staff_member.staff_type.in?(%w[doctor nurse])

      @appointment = current_practice.appointments
        .includes(:patient, :clinician, :appointment_slot, :encounter)
        .find(params[:appointment_id])

      head :forbidden unless @appointment.clinician_id == current_staff_member.id
    end
  end
end
