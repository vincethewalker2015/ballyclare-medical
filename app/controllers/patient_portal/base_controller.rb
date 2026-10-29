module PatientPortal
  class BaseController < ApplicationController
    layout "public"

    before_action :authenticate_patient_account!

    private

    def render_access_unavailable
      render "patient_portal/shared/access_unavailable", status: :forbidden
    end
  end
end
