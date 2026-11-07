class StripeOutageAlertMailer < ApplicationMailer
  def suspected(practice:)
    @practice = practice

    # Senior administrators have operational authority across their medical group.
    recipients = StaffMember.joins(:practice).where(
      active: true, access_level: "senior_staff_admin",
      practices: { medical_group_id: practice.medical_group_id }
    ).includes(:user).filter_map { |staff| staff.user.email.presence }

    # Include an active Chief of Group even when they are not a senior admin.
    chief = practice.medical_group.chief_of_group
    if chief && chief.staff_members.joins(:practice)
        .where(active: true, practices: { medical_group_id: practice.medical_group_id }).exists?
      recipients << chief.email if chief.email.present?
    end

    recipients = recipients.uniq
    return if recipients.empty?

    mail(
      to: recipients,
      subject: "Ballyclare Medical: suspected Stripe payment connectivity issue"
    )
  end
end
