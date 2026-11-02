module PatientPortal
  class ClinicalDocumentsController < BaseController
    def index
      link = current_patient_account.patient_account_links.approved
        .includes(:patient, :practice).first
      return render_access_unavailable unless link &&
        link.patient.practice_id == link.practice_id

      AuditEvent.create!(
        practice: link.practice,
        auditable: link,
        action: "clinical.patient_documents_viewed",
        metadata: { patient_id: link.patient_id, patient_account_id: current_patient_account.id }
      )

      @releases = ClinicalDocumentRelease
        .where(practice_id: link.practice_id, patient_id: link.patient_id)
        .order(released_at: :desc)
    end
  end
end
