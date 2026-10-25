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

      head :not_found unless @registration_request.patient_account.confirmed?
    end

    private

    def require_staff_administrator
      head :forbidden unless current_staff_member.staff_administration_access?
    end
  end
end
