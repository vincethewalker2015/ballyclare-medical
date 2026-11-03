module Staff
  class PatientPortalInvitationsController < BaseController
    before_action :require_staff_administrator

    def create
      patient = current_practice.patients.find(params[:patient_id])
      account = nil
      PatientAccount.transaction do
        account = PatientAccounts::CreateInvitation.call!(
          patient: patient, email: params[:email], staff_member: current_staff_member
        )
      end
      PatientPortalActivationJob.perform_later(account.id)
      redirect_to practice_patient_path(patient),
        notice: "Invitation queued. The patient must confirm their email and set a password before identity review."
    rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      redirect_to practice_patient_path(patient),
        alert: error.is_a?(ArgumentError) ? error.message : "Could not create an invitation. Check whether an account already exists for this email."
    end

    private

    def require_staff_administrator
      head :forbidden unless current_staff_member.staff_administration_access?
    end
  end
end
