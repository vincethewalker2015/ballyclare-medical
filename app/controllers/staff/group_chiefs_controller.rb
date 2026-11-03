module Staff
  class GroupChiefsController < BaseController
    def update
      group = current_practice.medical_group
      return head :forbidden unless chief_of_current_group? || (group.chief_of_group_id.nil? && group_authority_membership.present?)

      candidate = User.joins(staff_members: :practice)
        .where(staff_members: { active: true }, practices: { medical_group_id: group.id })
        .find_by(id: params[:user_id])
      return redirect_to practice_practices_path, alert: "Choose an active staff member in this medical group." unless candidate

      MedicalGroup.transaction do
        group.lock!
        # Only the current Chief can transfer ownership. Senior administrators
        # may appoint the first Chief only while the position is vacant.
        unless group.chief_of_group_id == current_user.id ||
            (group.chief_of_group_id.nil? && group_authority_membership.present?)
          return head :forbidden
        end

        group.update!(chief_of_group: candidate)
        AuditEvent.create!(
          practice: current_practice, user: current_user, auditable: group,
          action: "medical_group.chief_changed",
          metadata: { previous_chief_user_id: group.chief_of_group_id_before_last_save,
                      new_chief_user_id: candidate.id }
        )
      end

      redirect_to practice_practices_path, notice: "Chief of Group updated."
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      redirect_to practice_practices_path, alert: "This user cannot be appointed Chief of Group."
    end
  end
end
