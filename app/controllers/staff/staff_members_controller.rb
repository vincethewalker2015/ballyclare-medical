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
      @email = params.require(:staff_member)[:email].to_s.strip
      if @email.blank?
        @staff_member.errors.add(:base, "Enter an email address")
        return render :new, status: :unprocessable_content
      end

      newly_created_account = false

      StaffMember.transaction do
        @staff_member.user = Staff::ProvisionUserAccount.new(email: @email).call
        newly_created_account = @staff_member.user.previously_new_record?
        @staff_member.user.update!(invitation_pending_at: Time.current) if newly_created_account

        @staff_member.save!
      end

      @staff_member.user.send_reset_password_instructions if newly_created_account

      redirect_to practice_staff_members_path, notice: "Staff member created successfully."
    rescue ActiveRecord::RecordNotUnique
      @staff_member.errors.add(:user_id, "already belongs to this practice")
      render :new, status: :unprocessable_content
    rescue ActiveRecord::RecordInvalid => error
      if error.record.is_a?(User)
        @staff_member.errors.add(:base, "Enter a valid email address")
      end
      render :new, status: :unprocessable_content
    end

    def edit
      return head :forbidden unless staff_administrator?

      @staff_member = current_practice.staff_members.find(params[:id])
    end

    def update
      return head :forbidden unless staff_administrator?

      @staff_member = current_practice.staff_members.find(params[:id])
      attributes = staff_member_params
      if attributes[:staff_type].present? &&
         attributes[:staff_type] != @staff_member.staff_type &&
         @staff_member.access_level == "staff_clinician" &&
         !attributes[:staff_type].in?(%w[doctor nurse])
        @staff_member.errors.add(:staff_type, "cannot change while Staff Clinician access is assigned")
        return render :edit, status: :unprocessable_content
      end

      if @staff_member.update(attributes)
        redirect_to practice_staff_members_path, notice: "Staff details updated."
      else
        render :edit, status: :unprocessable_content
      end
    end

    def deactivate
      return head :forbidden unless staff_administrator?

      staff_member = current_practice.staff_members.find(params[:id])
      return head :forbidden if staff_member.id == current_staff_member.id

      unless current_staff_member.access_level == "senior_staff_admin" ||
             !staff_member.access_level.in?(%w[staff_admin senior_staff_admin])
        return head :forbidden
      end

      StaffMember.transaction do
        current_practice.lock!
        staff_member.lock!

        if staff_member.active? &&
           staff_member.access_level == "senior_staff_admin" &&
           !current_practice.staff_members.where(active: true, access_level: "senior_staff_admin")
             .where.not(id: staff_member.id).exists?
          staff_member.errors.add(:base, "The last active senior staff administrator cannot be deactivated")
        end

        if staff_member.active? &&
           Appointment.joins(:appointment_slot)
             .where(clinician_id: staff_member.id)
             .where(appointment_slots: { starts_at: Time.current.. })
             .where.not(status: "cancelled").exists?
          staff_member.errors.add(:base, "Review future appointments before deactivating this clinician")
        end

        staff_member.update!(active: false) if staff_member.errors.empty?
      end

      if staff_member.errors.any?
        redirect_to practice_staff_members_path, alert: staff_member.errors.full_messages.to_sentence
      else
        redirect_to practice_staff_members_path, notice: "Staff member deactivated."
      end
    end

    def reactivate
      return head :forbidden unless staff_administrator?

      staff_member = current_practice.staff_members.find(params[:id])

      unless current_staff_member.access_level == "senior_staff_admin" ||
             !staff_member.access_level.in?(%w[staff_admin senior_staff_admin])
        return head :forbidden
      end

      StaffMember.transaction do
        current_practice.lock!
        staff_member.lock!
        staff_member.update!(active: true) unless staff_member.active?
      end

      redirect_to practice_staff_members_path, notice: "Staff member reactivated."
    end

    def access_level
      return head :forbidden unless current_staff_member.access_level == "senior_staff_admin"

      staff_member = current_practice.staff_members.find(params[:id])
      requested_access_level = access_level_params[:access_level]

      if staff_member.id == current_staff_member.id &&
         requested_access_level != "senior_staff_admin"
        return head :forbidden
      end

      if requested_access_level != "senior_staff_admin" &&
         staff_member.access_level == "senior_staff_admin" &&
         staff_member.active? &&
         !current_practice.staff_members.where(active: true, access_level: "senior_staff_admin")
           .where.not(id: staff_member.id).exists?
        return redirect_to practice_staff_members_path,
          alert: "The last active senior staff administrator cannot be demoted."
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
        :first_name, :last_name, :staff_type, :registration_number
      )
    end

    def access_level_params
      params.require(:staff_member).permit(:access_level)
    end
  end
end
