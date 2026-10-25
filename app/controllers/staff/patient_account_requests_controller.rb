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

      method = params.require(:verification_method)
      route = params.require(:patient_route)
      unless PatientAccountLink::VERIFICATION_METHODS.include?(method) &&
          PatientRegistrationRequest::PATIENT_ROUTES.include?(route) &&
          params[:identity_checked] == "1"
        return redirect_to practice_patient_account_request_path(request_record),
          alert: "Choose a patient route and confirm the approved identity check."
      end

      patient = if route == "existing_patient"
        current_practice.patients.find(params.require(:patient_id))
      end
      if route == "new_patient" &&
          [ request_record.first_name, request_record.last_name, request_record.date_of_birth ].any?(&:blank?)
        return redirect_to practice_patient_account_request_path(request_record),
          alert: "Registration details are incomplete. Create and verify a clinical record manually."
      end

      request_record.with_lock do
        return redirect_to practice_patient_account_request_path(request_record),
          alert: "This registration has already been reviewed." unless request_record.review_status == "awaiting_review"

        request_record.update!(
          review_status: "verified",
          patient_route: route,
          selected_patient: patient,
          verification_method: method,
          identity_verified_at: Time.current,
          reviewed_by: current_staff_member
        )
        AuditEvent.create!(
          practice: current_practice,
          user: current_user,
          auditable: request_record,
          action: "patient_account.identity_verified",
          metadata: { patient_route: route, patient_id: patient&.id,
                      staff_member_id: current_staff_member.id }
        )
      end

      redirect_to practice_patient_account_request_path(request_record),
        notice: "Identity verification recorded. Senior Staff Admin approval is required."
    end

    def approve
      return head :forbidden unless current_staff_member.senior_administration_access?

      request_record = current_practice.patient_registration_requests
        .joins(:patient_account)
        .where.not(patient_accounts: { confirmed_at: nil })
        .find(params[:id])
      return redirect_to practice_patient_account_request_path(request_record),
        alert: "Identity verification is required before approval." unless request_record.review_status == "verified"

      request_record.with_lock do
        request_record.update!(review_status: "approved", approved_by: current_staff_member,
          approved_at: Time.current)
      end
      CompletePatientRegistrationJob.perform_later(request_record.id)
      redirect_to practice_patient_account_request_path(request_record),
        notice: "Registration approved. Clinical record processing has been queued."
    end

    private

    def require_staff_administrator
      head :forbidden unless current_staff_member.staff_administration_access?
    end
  end
end
