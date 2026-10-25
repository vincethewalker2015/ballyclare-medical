module PatientAccounts
  class SessionsController < Devise::SessionsController
    layout "public"

    protected

    def after_sign_in_path_for(_resource)
      patient_portal_path
    end

    def after_sign_out_path_for(_resource_or_scope)
      new_patient_account_session_path
    end
  end
end
