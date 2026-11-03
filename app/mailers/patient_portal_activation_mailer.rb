class PatientPortalActivationMailer < ApplicationMailer
  def invitation(account:, confirmation_token:, password_token:)
    @confirmation_url = confirmation_url(account, confirmation_token: confirmation_token)
    @password_url = edit_password_url(account, reset_password_token: password_token)

    mail(to: account.email, subject: "Welcome to Ballyclare Medical – Activate your patient portal")
  end
end
