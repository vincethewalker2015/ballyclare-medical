module PatientAccounts
  class RegistrationsController < Devise::RegistrationsController
    layout "public"

    protected

    def after_inactive_sign_up_path_for(_resource)
      new_patient_account_session_path
    end
  end
end
