module PatientPortal
  class ClinicalDocumentsController < BaseController
    def download
      link = current_patient_account.patient_account_links.approved
        .includes(:patient, :practice).first
      return render_access_unavailable unless link &&
        link.patient.practice_id == link.practice_id

      release = ClinicalDocumentRelease.find_by(
        id: params[:id], practice_id: link.practice_id, patient_id: link.patient_id, printable: true
      )
      return head :not_found unless release

      pdf = ClinicalDocuments::RenderPdf.new(release: release).call
      AuditEvent.create!(
        practice: link.practice, auditable: release,
        action: "clinical.patient_document_downloaded",
        metadata: { patient_id: link.patient_id, patient_account_id: current_patient_account.id }
      )
      response.headers["Cache-Control"] = "private, no-store"
      send_data pdf, type: "application/pdf", disposition: "attachment",
        filename: "clinical-document-#{release.id}.pdf"
    end

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

      @patient_link = link
      @releases = ClinicalDocumentRelease
        .where(practice_id: link.practice_id, patient_id: link.patient_id)
        .order(released_at: :desc)
    end
  end
end
