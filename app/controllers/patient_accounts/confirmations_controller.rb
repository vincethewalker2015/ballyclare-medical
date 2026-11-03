module PatientAccounts
  class ConfirmationsController < Devise::ConfirmationsController
    layout "public"

    protected

    def after_confirmation_path_for(_resource_name, _resource)
      if params[:reset_password_token].present?
        edit_patient_account_password_path(reset_password_token: params[:reset_password_token])
      else
        new_patient_account_session_path
      end
    end
  end
end
