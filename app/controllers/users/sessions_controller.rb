module Users
  class SessionsController < Devise::SessionsController
    def create
      self.resource = warden.authenticate!(auth_options)

      if resource.staff_members.exists?(active: false) &&
          !resource.staff_members.exists?(active: true) &&
          resource.patient.nil?
        @inactive_account_alert = "Your staff account is inactive. Please contact your practice administrator."
        resource.password = nil
        return render :new, status: :unprocessable_content
      end

      sign_in(resource_name, resource)
      set_flash_message!(:notice, :signed_in) if is_flashing_format?
      respond_with resource, location: after_sign_in_path_for(resource)
    end
  end
end
