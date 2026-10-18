module Staff
  class StaffMembersController < BaseController
    def index
      @staff_members = current_practice.staff_members.order(:last_name, :first_name)
    end

    def new
      return head :forbidden unless staff_administrator?

      @staff_member = current_practice.staff_members.new
    end

    def create
      return head :forbidden unless staff_administrator?

      @staff_member = current_practice.staff_members.new(staff_member_params)
      @staff_member.access_level = "staff"

      if @staff_member.save
        redirect_to practice_staff_members_path, notice: "Staff member created successfully."
      else
        render :new, status: :unprocessable_content
      end
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

    def staff_administrator?
      current_staff_member.access_level.in?(%w[staff_admin senior_staff_admin])
    end

    def staff_member_params
      params.require(:staff_member).permit(
        :user_id, :first_name, :last_name, :staff_type,
        :default_appointment_duration, :registration_number
      )
    end

    def access_level_params
      params.require(:staff_member).permit(:access_level)
    end
  end
end
