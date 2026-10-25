module Staff
  class PatientAccountRequestsController < BaseController
    before_action :require_staff_administrator

    def index
      @accounts = PatientAccount.where.not(confirmed_at: nil)
        .where.not(id: PatientAccountLink.where(practice_id: current_practice.id)
          .select(:patient_account_id))
        .order(:created_at)
    end

    private

    def require_staff_administrator
      head :forbidden unless current_staff_member.staff_administration_access?
    end
  end
end
