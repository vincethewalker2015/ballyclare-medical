module Staff
  class PatientAccountRequestsController < BaseController
    before_action :require_staff_administrator

    def index
      # Only show records explicitly associated with this practice.
      # Unassigned accounts cannot safely appear in a practice-wide queue.
      @links = current_practice.patient_account_links
        .includes(:patient_account)
        .where(status: "pending")
        .order(:created_at)
    end

    private

    def require_staff_administrator
      head :forbidden unless current_staff_member.staff_administration_access?
    end
  end
end
