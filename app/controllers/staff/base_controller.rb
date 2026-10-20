module Staff
  class BaseController < ApplicationController
    layout "practice"

    before_action :authenticate_user!
    before_action :set_current_staff_member
    before_action :set_current_practice

    private

    attr_reader :current_staff_member, :current_practice

    def require_operational_access
      head :forbidden unless current_staff_member.operational_access?
    end

    def set_current_staff_member
      @current_staff_member = current_user.staff_members.first

      return if @current_staff_member&.active?

      render "staff/base/inactive", status: :forbidden
    end

    def set_current_practice
      return if performed?

      @current_practice = current_staff_member.practice
    end
  end
end
