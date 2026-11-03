module PatientAccounts
  # Shared invitation flow for both staff-created patients and existing records.
  # Must be called inside the caller's transaction; no portal link is approved here.
  class CreateInvitation
    def self.call!(patient:, email:, staff_member:)
      address = email.to_s.strip.downcase
      raise ArgumentError, "Enter a valid patient email address." unless Devise.email_regexp.match?(address)
      raise ArgumentError, "This patient already has a portal connection." if patient.patient_account_link.present?
      raise ArgumentError, "This email already has a patient portal account." if PatientAccount.exists?(email: address)
      raise ArgumentError, "You cannot invite patients in another practice." unless patient.practice_id == staff_member.practice_id
      raise ArgumentError, "Administrator access is required." unless staff_member.active? && staff_member.staff_administration_access?

      account = PatientAccount.new(email: address, password: Devise.friendly_token(48))
      # Send a single activation email after commit, not Devise's separate confirmation email.
      account.skip_confirmation_notification!
      account.save!
      PatientRegistrationRequest.create!(
        practice: patient.practice, patient_account: account,
        first_name: patient.first_name, last_name: patient.last_name,
        date_of_birth: patient.date_of_birth
      )
      AuditEvent.create!(
        practice: patient.practice, user: staff_member.user, auditable: patient,
        action: "patient_account.invitation_created",
        metadata: { patient_account_id: account.id }
      )
      account
    end
  end
end
