module Staff
  class PracticesController < BaseController
    before_action :require_senior_administrator

    def index
      @practices = current_practice.medical_group.practices.order(:name)
      @group = current_practice.medical_group
      @chief_candidates = User.joins(staff_members: :practice)
        .where(staff_members: { active: true }, practices: { medical_group_id: @group.id })
        .distinct.order(:email)
    end

    def new
      @practice = current_practice.medical_group.practices.new(
        timezone: current_practice.timezone, currency: current_practice.currency,
        country_code: current_practice.country_code
      )
    end

    def create
      group = current_practice.medical_group
      @practice = group.practices.new(practice_params)
      @practice.active = true

      # A clinician Chief retains their clinical membership. Assign an existing
      # group Senior Staff Admin to the new practice for local administration.
      administrator = if current_staff_member.access_level == "senior_staff_admin"
        current_staff_member
      else
        StaffMember.joins(:practice)
          .where(active: true, access_level: "senior_staff_admin",
            practices: { medical_group_id: group.id })
          .order(:created_at, :id).first
      end

      unless administrator
        @practice.errors.add(:base, "An active Senior Staff Admin is required to set up a new practice")
        return render :new, status: :unprocessable_content
      end

      Practice.transaction do
        @practice.save!
        administrator.user.staff_members.create!(
          practice: @practice, first_name: administrator.first_name,
          last_name: administrator.last_name, staff_type: "administrator",
          access_level: "senior_staff_admin", active: true
        )
        AuditEvent.create!(practice: @practice, user: current_user,
          auditable: @practice, action: "practice.created",
          metadata: { medical_group_id: group.id })
      end
      redirect_to practice_practices_path, notice: "Practice created successfully."
    rescue ActiveRecord::RecordInvalid => error
      @practice.errors.add(:base, error.record.errors.full_messages.to_sentence) if error.record != @practice
      render :new, status: :unprocessable_content
    end

    def edit
      @practice = group_practices.find(params[:id])
    end

    def update
      @practice = group_practices.find(params[:id])
      if @practice.update(practice_params)
        AuditEvent.create!(practice: @practice, user: current_user,
          auditable: @practice, action: "practice.updated",
          metadata: { medical_group_id: @practice.medical_group_id })
        redirect_to practice_practices_path, notice: "Practice details updated."
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def group_practices
      current_practice.medical_group.practices
    end

    def require_senior_administrator
      head :forbidden unless can_administer_current_group?
    end

    def practice_params
      params.require(:practice).permit(
        :name, :phone, :email, :address_line_1, :address_line_2,
        :city, :region, :postal_code, :country_code, :timezone, :currency
      )
    end
  end
end
