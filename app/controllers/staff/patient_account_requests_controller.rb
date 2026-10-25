module Staff
  class PatientAccountRequestsController < BaseController
    before_action :require_staff_administrator

    def index
      @registration_requests = current_practice.patient_registration_requests
        .joins(:patient_account)
        .where.not(patient_accounts: { confirmed_at: nil })
        .includes(:patient_account)
        .order(:created_at)

      @links = current_practice.patient_account_links
        .includes(:patient_account, :patient)
        .where(status: "pending")
        .order(:created_at)
    end

    def show
      @registration_request = current_practice.patient_registration_requests
        .includes(:patient_account)
        .find(params[:id])

      return head :not_found unless @registration_request.patient_account.confirmed?

      @patient_search = params[:patient_search].to_s.strip.first(100)
      @matching_patients = []
      if @patient_search.present?
        term = "%#{ActiveRecord::Base.sanitize_sql_like(@patient_search)}%"
        @matching_patients = current_practice.patients
          .where("first_name ILIKE :term OR last_name ILIKE :term OR patient_number ILIKE :term OR (first_name || ' ' || last_name) ILIKE :term",
            term: term)
          .order(:last_name, :first_name).limit(20).to_a
      end
    end

    def verify
      request_record = current_practice.patient_registration_requests
        .joins(:patient_account)
        .where.not(patient_accounts: { confirmed_at: nil })
        .find(params[:id])

      patient = current_practice.patients.find(params.require(:patient_id))
      method = params.require(:verification_method)
      unless PatientAccountLink::VERIFICATION_METHODS.include?(method) &&
          params[:identity_checked] == "1"
        return redirect_to practice_patient_account_request_path(request_record),
          alert: "Confirm the identity check and select a valid verification method."
      end

      ActiveRecord::Base.transaction do
        link = PatientAccountLink.create!(
          practice: current_practice,
          patient_account: request_record.patient_account,
          patient: patient,
          status: "pending",
          verification_method: method,
          verified_at: Time.current,
          verified_by: current_staff_member
        )

        AuditEvent.create!(
          practice: current_practice,
          user: current_user,
          auditable: link,
          action: "patient_account.identity_verified",
          metadata: { patient_id: patient.id, verification_method: method,
                      staff_member_id: current_staff_member.id }
        )
      end

      redirect_to practice_patient_account_request_path(request_record),
        notice: "Identity verification recorded. Senior Staff Admin approval is still required."
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      redirect_to practice_patient_account_request_path(params[:id]),
        alert: "This account or patient is already connected, or the verification could not be recorded."
    end

    private

    def require_staff_administrator
      head :forbidden unless current_staff_member.staff_administration_access?
    end
  end
end
