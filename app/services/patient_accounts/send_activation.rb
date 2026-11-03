module PatientAccounts
  # Invoked after the invitation transaction commits. Uses Devise's own
  # confirmation and password-reset tokens so both links retain normal expiry.
  class SendActivation
    def self.call!(account:)
      raise ArgumentError, "Account already confirmed" if account.confirmed?

      account.send(:generate_confirmation_token!)
      confirmation_token = account.instance_variable_get(:@raw_confirmation_token)
      password_token = account.send(:set_reset_password_token)

      PatientPortalActivationMailer.invitation(
        account: account,
        confirmation_token: confirmation_token,
        password_token: password_token
      ).deliver_now
    end
  end
end
