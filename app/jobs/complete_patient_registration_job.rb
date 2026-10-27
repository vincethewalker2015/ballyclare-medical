class CompletePatientRegistrationJob < ApplicationJob
  queue_as :default

  def perform(request_id)
    request_record = PatientRegistrationRequest.find(request_id)

    request_record.with_lock do
      return if request_record.review_status == "completed"
      return unless request_record.review_status.in?(%w[approved processing])
      return unless request_record.patient_account.confirmed?
      return unless request_record.approved_by&.senior_administration_access?
      return unless request_record.reviewed_by.present? &&
        request_record.identity_verified_at.present? &&
        PatientAccountLink::VERIFICATION_METHODS.include?(request_record.verification_method)

      patient = if request_record.patient_route == "existing_patient"
        request_record.practice.patients.find(request_record.selected_patient_id)
      elsif request_record.patient_route == "new_patient"
        Patient.create!(
          practice: request_record.practice,
          first_name: request_record.first_name,
          last_name: request_record.last_name,
          date_of_birth: request_record.date_of_birth
        )
      else
        raise ArgumentError, "Patient route must be selected before processing"
      end

      if PatientAccountLink.exists?(patient_id: patient.id) ||
          PatientAccountLink.exists?(patient_account_id: request_record.patient_account_id)
        request_record.update!(review_status: "failed", processed_at: Time.current)
        Rails.logger.warn(
          "Patient registration link conflict: request=#{request_record.id} patient=#{patient.id}"
        )
        return
      end

      link = PatientAccountLink.create!(
        practice: request_record.practice,
        patient_account: request_record.patient_account,
        patient: patient,
        status: "approved",
        verification_method: request_record.verification_method,
        verified_at: request_record.identity_verified_at,
        verified_by: request_record.reviewed_by,
        approved_at: request_record.approved_at
      )

      AuditEvent.create!(
        practice: request_record.practice,
        user: request_record.approved_by.user,
        auditable: link,
        action: "patient_account.approved",
        metadata: { registration_request_id: request_record.id,
                    patient_id: patient.id,
                    approving_staff_member_id: request_record.approved_by_id }
      )
      request_record.update!(review_status: "completed", processed_at: Time.current)
    end
  end
end
