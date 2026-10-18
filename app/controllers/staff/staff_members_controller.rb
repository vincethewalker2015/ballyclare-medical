module Staff
  class StaffMembersController < BaseController
    def index
      @staff_members = current_practice.staff_members.order(:last_name, :first_name)
    end
  end
end
