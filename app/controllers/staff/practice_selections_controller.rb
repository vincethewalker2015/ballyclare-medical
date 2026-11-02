module Staff
  class PracticeSelectionsController < BaseController
    def update
      practice = current_staff_member.practice.medical_group.practices.find_by(id: params[:practice_id])

      unless current_staff_member.can_access_practice?(practice)
        return head :forbidden
      end

      session[:staff_practice_id] = practice.id
      redirect_to practice_appointments_path, notice: "Practice switched successfully."
    end
  end
end
