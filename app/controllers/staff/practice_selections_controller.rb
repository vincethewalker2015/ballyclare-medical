module Staff
  class PracticeSelectionsController < BaseController
    def update
      practice = authorized_practices.find_by(id: params[:practice_id])
      return head :forbidden unless practice

      session[:staff_practice_id] = practice.id
      redirect_to practice_appointments_path, notice: "Practice switched successfully."
    end
  end
end
