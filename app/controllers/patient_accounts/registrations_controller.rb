module PatientAccounts
  class RegistrationsController < Devise::RegistrationsController
    layout "public"

    def new
      super
    end

    def create
      selected_practice = Practice.find_by(id: params.dig(:patient_account, :practice_id))
      unless selected_practice
        build_resource(sign_up_params)
        resource.errors.add(:base, "Please select a valid practice")
        clean_up_passwords resource
        return render :new, status: :unprocessable_content
      end

      ActiveRecord::Base.transaction do
        build_resource(sign_up_params)
        resource.save!
        PatientRegistrationRequest.create!(
          practice: selected_practice, patient_account: resource
        )
      end

      yield resource if block_given?
      if resource.persisted?
        if resource.active_for_authentication?
          set_flash_message! :notice, :signed_up
          sign_up(resource_name, resource)
          respond_with resource, location: after_sign_up_path_for(resource)
        else
          set_flash_message! :notice, :"signed_up_but_#{resource.inactive_message}"
          expire_data_after_sign_in!
          respond_with resource, location: after_inactive_sign_up_path_for(resource)
        end
      end
    rescue ActiveRecord::RecordInvalid
      clean_up_passwords resource
      set_minimum_password_length
      render :new, status: :unprocessable_content
    end

    protected

    def after_inactive_sign_up_path_for(_resource)
      new_patient_account_session_path
    end
  end
end
