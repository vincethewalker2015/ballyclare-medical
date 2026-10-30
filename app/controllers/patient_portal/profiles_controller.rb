module PatientPortal
  class ProfilesController < BaseController
    before_action :load_patient

    def show
    end

    def edit
    end

    def update
      attributes = params.require(:patient_account).permit(:email, :password, :password_confirmation, :current_password)
      if current_patient_account.update_with_password(attributes)
        bypass_sign_in(current_patient_account, scope: :patient_account)
        redirect_to patient_portal_profile_path, notice: "Account details updated. Check your email if confirmation is required."
      else
        current_patient_account.password = nil
        current_patient_account.password_confirmation = nil
        render :edit, status: :unprocessable_content
      end
    end

    private

    def load_patient
      patient_account_link = current_patient_account.patient_account_links.approved.includes(:patient).first
      return render_access_unavailable unless patient_account_link &&
        patient_account_link.patient.practice_id == patient_account_link.practice_id

      @patient = patient_account_link.patient
    end
  end
end
