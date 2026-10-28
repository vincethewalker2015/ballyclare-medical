module Staff
  class PatientAccountRequestsController < BaseController
    before_action :require_staff_administrator

    def index
      @request_search = params[:request_search].to_s.strip.first(100)
      @page = [ params[:page].to_i, 1 ].max
      requests = current_practice.patient_registration_requests
        .joins(:patient_account)
        .where.not(patient_accounts: { confirmed_at: nil })
      if @request_search.present?
        term = "%#{ActiveRecord::Base.sanitize_sql_like(@request_search)}%"
        requests = requests.where(
          "patient_registration_requests.first_name ILIKE :term OR " \
          "patient_registration_requests.last_name ILIKE :term OR " \
          "CONCAT_WS(' ', patient_registration_requests.first_name, patient_registration_requests.last_name) ILIKE :term OR " \
          "patient_accounts.email ILIKE :term", term: term
        )
      end
      @request_count = requests.count
      @total_pages = [ (@request_count / 5.0).ceil, 1 ].max
      @page = [ @page, @total_pages ].min
      @registration_requests = requests.includes(:patient_account)
        .order(created_at: :desc, id: :desc).offset((@page - 1) * 5).limit(5)
      @links_by_account_id = current_practice.patient_account_links
        .where(patient_account_id: @registration_requests.map(&:patient_account_id))
        .index_by(&:patient_account_id)
    end

    def show
      @registration_request = current_practice.patient_registration_requests
        .includes(:patient_account)
        .find(params[:id])

      return head :not_found unless @registration_request.patient_account.confirmed?

      @account_link = current_practice.patient_account_links
        .where(patient_account_id: @registration_request.patient_account_id).first

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
      approved = false
      request_record.with_lock do
        if request_record.review_status == "verified" &&
            request_record.reviewed_by.present? &&
            request_record.identity_verified_at.present? &&
            PatientAccountLink::VERIFICATION_METHODS.include?(request_record.verification_method) &&
            PatientRegistrationRequest::PATIENT_ROUTES.include?(request_record.patient_route) &&
            (request_record.patient_route == "new_patient" ||
             request_record.selected_patient_id.present?)
          request_record.update!(review_status: "approved", approved_by: current_staff_member,
            approved_at: Time.current)
          approved = true
        end
      end
      return redirect_to practice_patient_account_request_path(request_record),
        alert: "A verified, complete request is required before approval." unless approved

      CompletePatientRegistrationJob.perform_later(request_record.id)
      redirect_to practice_patient_account_request_path(request_record),
        notice: "Registration approved. Clinical record processing has been queued."
    end

    def reinstate
      return head :forbidden unless current_staff_member.senior_administration_access?

      link = current_practice.patient_account_links.find(params[:id])
      method = params[:verification_method].to_s
      reason = params[:reinstatement_reason].to_s.strip.first(500)
      unless params[:identity_checked] == "1" &&
          PatientAccountLink::VERIFICATION_METHODS.include?(method) &&
          reason.length >= 10
        return redirect_to practice_patient_account_requests_path,
          alert: "Fresh identity verification and a reason of at least 10 characters are required."
      end

      reinstated = false
      link.with_lock do
        if link.status == "revoked" && link.patient_account.confirmed? &&
            link.patient.practice_id == current_practice.id
          link.update!(
            status: "approved", verification_method: method,
            verified_at: Time.current, verified_by: current_staff_member,
            approved_at: Time.current
          )
          AuditEvent.create!(
            practice: current_practice, user: current_user, auditable: link,
            action: "patient_account.link_reinstated",
            metadata: { staff_member_id: current_staff_member.id,
                        patient_id: link.patient_id, patient_account_id: link.patient_account_id,
                        verification_method: method, reason: reason }
          )
          reinstated = true
        end
      end

      redirect_to practice_patient_account_requests_path,
        (reinstated ? { notice: "Patient portal access reinstated." } :
          { alert: "This patient account link cannot be reinstated." })
    end

    def revoke
      return head :forbidden unless current_staff_member.senior_administration_access?

      link = current_practice.patient_account_links.find(params[:id])
      revoked = false
      link.with_lock do
        if link.approved?
          link.update!(status: "revoked")
          AuditEvent.create!(
            practice: current_practice, user: current_user, auditable: link,
            action: "patient_account.link_revoked",
            metadata: { staff_member_id: current_staff_member.id,
                        patient_id: link.patient_id, patient_account_id: link.patient_account_id }
          )
          revoked = true
        end
      end

      redirect_to practice_patient_account_requests_path,
        (revoked ? { notice: "Patient account access revoked." } : { alert: "This link is not approved." })
    end

    private

    def require_staff_administrator
      head :forbidden unless current_staff_member.staff_administration_access?
    end
  end
end
