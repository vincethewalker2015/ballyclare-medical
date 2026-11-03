module Staff
  class BaseController < ApplicationController
    layout "practice"

    helper_method :authorized_practices, :chief_of_current_group?, :can_administer_current_group?, :can_administer_current_practice?

    before_action :authenticate_user!
    before_action :set_current_staff_member
    before_action :set_current_practice

    private

    attr_reader :current_staff_member, :current_practice

    def require_operational_access
      return head :forbidden unless current_staff_member.operational_access?

      # A Chief's group-wide practice selection must not turn a clinician
      # membership at another practice into local patient-record access.
      return if current_staff_member.practice_id == current_practice.id
      return if current_staff_member.senior_administration_access?

      head :forbidden
    end

    def set_current_staff_member
      @current_staff_member = current_user.staff_members.where(active: true).order(:created_at, :id).first

      return if @current_staff_member&.active?

      render "staff/base/inactive", status: :forbidden
    end

    def group_authority_membership
      return nil unless current_practice && current_staff_member&.active?

      current_user.staff_members.where(active: true, access_level: "senior_staff_admin")
        .joins(:practice).where(practices: { medical_group_id: current_practice.medical_group_id })
        .order(:created_at, :id).first
    end

    def chief_of_current_group?
      current_practice.present? && current_staff_member&.active? &&
        current_practice.medical_group.chief_of_group_id == current_user.id
    end

    def authorized_practices
      group = current_practice.medical_group
      if chief_of_current_group? || group_authority_membership.present?
        group.practices
      else
        group.practices.where(id: current_user.staff_members.where(active: true).select(:practice_id))
      end
    end

    def can_administer_current_practice?
      current_staff_member&.active? &&
        (current_staff_member.staff_administration_access? || chief_of_current_group?)
    end

    def can_administer_current_group?
      return false unless current_practice && current_staff_member&.active?

      chief_of_current_group? || group_authority_membership.present?
    end

    def set_current_practice
      return if performed?

      @current_practice = current_staff_member.practice
      return if session[:staff_practice_id].blank?

      selected_practice = Practice.find_by(id: session[:staff_practice_id])
      # A group Chief can select any practice in their group; an active senior
      # membership grants equivalent operational access, not clinical authority.
      local_membership = current_user.staff_members.where(active: true, practice_id: selected_practice&.id).first
      senior_membership = current_user.staff_members.where(active: true, access_level: "senior_staff_admin")
        .joins(:practice).where(practices: { medical_group_id: selected_practice&.medical_group_id })
        .order(:created_at, :id).first
      chief_membership = if selected_practice&.medical_group&.chief_of_group_id == current_user.id
        current_user.staff_members.where(active: true)
          .joins(:practice).where(practices: { medical_group_id: selected_practice.medical_group_id })
          .order(:created_at, :id).first
      end

      if selected_practice && (local_membership || senior_membership || chief_membership)
        @current_practice = selected_practice
        @current_staff_member = local_membership || senior_membership || chief_membership
      else
        session.delete(:staff_practice_id)
      end
    end
  end
end
