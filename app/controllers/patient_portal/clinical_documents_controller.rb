module PatientPortal
  class ClinicalDocumentsController < BaseController
    def index
      link = current_patient_account.patient_account_links.approved
        .includes(:patient, :practice).first
      return render_access_unavailable unless link &&
        link.patient.practice_id == link.practice_id

      @releases = ClinicalDocumentRelease
        .where(practice_id: link.practice_id, patient_id: link.patient_id)
        .order(released_at: :desc)
    end
  end
end
