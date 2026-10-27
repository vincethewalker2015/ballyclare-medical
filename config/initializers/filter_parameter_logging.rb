# Restart Rails after changing this file.
# Rails filters matching parameter keys in controller logs and inspected parameter hashes.
# Avoid filtering generic keys such as :name, :reason or :status, which would hide
# unrelated diagnostic information. Use explicit clinical/contact field names.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt,
  :certificate, :otp, :ssn, :cvv, :cvc,
  :first_name, :middle_names, :last_name, :date_of_birth,
  :phone, :mobile, :telephone,
  :address_line_1, :address_line_2, :postcode,
  :consultation_reason, :patient_notes, :clinical_notes,
  :cancellation_reason, :symptoms, :medical_history,
  :patient_number, :nhs_number
]
