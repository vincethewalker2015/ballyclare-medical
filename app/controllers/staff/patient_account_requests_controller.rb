module Staff
  class PatientAccountRequestsController < BaseController
    before_action :require_staff_administrator

    def index
      @links = current_practice.patient_account_links
        .includes(:patient_account, :patient)
        .where(status: "pending")
        .order(:created_at)
    end

    def create
      email = params.require(:email).to_s.strip.downcase
      account = PatientAccount.find_by(email: email)
      patient = current_practice.patients.find(params.require(:patient_id))

      unless account&.confirmed?
        return redirect_to practice_patient_account_requests_path,
          alert: "No confirmed patient account was found for that email address."
      end

      PatientAccountLink.create!(
        practice: current_practice,
        patient: patient,
        patient_account: account
      )

      redirect_to practice_patient_account_requests_path,
        notice: "Account assigned for identity verification. No portal access has been granted."
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      redirect_to practice_patient_account_requests_path,
        alert: "This account or patient record already has a connection, or the assignment is invalid."
    end

    private

    def require_staff_administrator
      head :forbidden unless current_staff_member.staff_administration_access?
    end
  end
end
