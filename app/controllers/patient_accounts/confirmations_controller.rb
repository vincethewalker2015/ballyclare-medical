module PatientAccounts
  class ConfirmationsController < Devise::ConfirmationsController
    layout "public"

    protected

    def after_confirmation_path_for(_resource_name, _resource)
      new_patient_account_session_path
    end
  end
end
