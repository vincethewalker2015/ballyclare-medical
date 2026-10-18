module Staff
  class StaffMembersController < BaseController
    def index
      @staff_members = current_practice.staff_members.order(:last_name, :first_name)
    end

    def access_level
      return head :forbidden unless current_staff_member.access_level == "senior_staff_admin"

      staff_member = current_practice.staff_members.find(params[:id])
      requested_access_level = access_level_params[:access_level]

      if staff_member.id == current_staff_member.id &&
         requested_access_level != "senior_staff_admin"
        return head :forbidden
      end

      if staff_member.update(access_level_params)
        redirect_to practice_staff_members_path, notice: "Staff access level updated."
      else
        redirect_to practice_staff_members_path, alert: staff_member.errors.full_messages.to_sentence
      end
    end

    private

    def access_level_params
      params.require(:staff_member).permit(:access_level)
    end
  end
end
