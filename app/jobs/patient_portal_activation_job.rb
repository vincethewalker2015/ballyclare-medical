# Deliver activation outside the patient-creation transaction so transient mail
# failures do not strand an invitation without a retry.
class PatientPortalActivationJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: 30.seconds, attempts: 5

  def perform(account_id)
    account = PatientAccount.find(account_id)
    return if account.confirmed?

    PatientAccounts::SendActivation.call!(account: account)
  end
end
