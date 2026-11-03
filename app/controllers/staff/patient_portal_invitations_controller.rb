module Staff
  class PatientPortalInvitationsController < BaseController
    before_action :require_staff_administrator

    def create
      patient = current_practice.patients.find(params[:patient_id])
      email = params[:email].to_s.strip.downcase

      if email.blank? || !Devise.email_regexp.match?(email)
        return redirect_to practice_patient_path(patient), alert: "Enter a valid patient email address."
      end
      if patient.patient_account_link.present?
        return redirect_to practice_patient_path(patient), alert: "This patient already has a portal connection. Review it in Patient accounts."
      end
      if PatientAccount.where(email: email).exists?
        return redirect_to practice_patient_path(patient), alert: "This email already has a patient portal account. Use the existing account review process."
      end

      account = nil
      PatientAccount.transaction do
        # Never issue staff-selected passwords or an approved clinical link.
        account = PatientAccount.new(email: email, password: Devise.friendly_token(48))
        account.save!
        PatientRegistrationRequest.create!(
          practice: current_practice, patient_account: account,
          first_name: patient.first_name, last_name: patient.last_name,
          date_of_birth: patient.date_of_birth
        )
        AuditEvent.create!(
          practice: current_practice, user: current_user, auditable: patient,
          action: "patient_account.invitation_created",
          metadata: { patient_account_id: account.id }
        )
      end

      # The patient receives an email confirmation and password-setting instructions.
      # Confirmation alone does not grant any access to the clinical record.
      account.send_reset_password_instructions
      redirect_to practice_patient_path(patient),
        notice: "Invitation sent. The patient must confirm their email and set a password before identity review."
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      redirect_to practice_patient_path(patient),
        alert: "Could not create an invitation. Check whether an account already exists for this email."
    end

    private

    def require_staff_administrator
      head :forbidden unless current_staff_member.staff_administration_access?
    end
  end
end
