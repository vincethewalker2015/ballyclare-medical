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

      details = params.fetch(:patient_account, {}).permit(:first_name, :last_name, :date_of_birth)
      unless details[:first_name].present? && details[:last_name].present? &&
          details[:date_of_birth].present? && valid_date_of_birth?(details[:date_of_birth])
        build_resource(sign_up_params)
        resource.errors.add(:base, "Enter your first name, surname and a valid date of birth")
        clean_up_passwords resource
        return render :new, status: :unprocessable_content
      end

      ActiveRecord::Base.transaction do
        build_resource(sign_up_params)
        resource.save!
        PatientRegistrationRequest.create!(
          practice: selected_practice, patient_account: resource,
          first_name: details[:first_name].strip, last_name: details[:last_name].strip,
          date_of_birth: Date.iso8601(details[:date_of_birth])
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

    private

    def valid_date_of_birth?(value)
      date = Date.iso8601(value)
      date <= Date.current && date >= 120.years.ago.to_date
    rescue Date::Error
      false
    end

    protected

    def after_inactive_sign_up_path_for(_resource)
      new_patient_account_session_path
    end
  end
end
