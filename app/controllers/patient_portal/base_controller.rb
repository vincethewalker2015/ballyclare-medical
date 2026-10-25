module PatientPortal
  class BaseController < ApplicationController
    layout "public"

    before_action :authenticate_patient_account!
  end
end
