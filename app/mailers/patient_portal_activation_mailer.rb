class PatientPortalActivationMailer < ApplicationMailer
  def invitation(account:, confirmation_token:, password_token:)
    @confirmation_url = patient_account_confirmation_url(confirmation_token: confirmation_token)
    @password_url = edit_patient_account_password_url(reset_password_token: password_token)

    mail(to: account.email, subject: "Welcome to Ballyclare Medical – Activate your patient portal")
  end
end
