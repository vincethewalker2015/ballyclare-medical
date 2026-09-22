FactoryBot.define do
  factory :practice do
    sequence(:name) { |n| "Practice #{n}" }
    timezone { "Europe/London" }
    currency { "GBP" }
    country_code { "GB" }
  end

  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }
  end

  factory :role do
    sequence(:name) { |n| "role_#{n}" }
  end

  factory :user_role do
    user
    role
  end

  factory :staff_member do
    practice
    user
    staff_type { "doctor" }
    default_appointment_duration { 20 }
  end

  factory :patient do
    practice
    sequence(:patient_number) { |n| "P#{n.to_s.rjust(6, '0')}" }
    first_name { "Jane" }
    last_name { "Doe" }
    date_of_birth { Date.new(1990, 1, 1) }
  end

  factory :patient_identifier do
    patient
    identifier_type { "nhs_number" }
    sequence(:identifier_value) { |n| format("%010d", n) }
  end

  factory :availability_block do
    practice
    clinician { association(:staff_member, practice: practice) }
    starts_at { 1.day.from_now.change(hour: 9, min: 0) }
    ends_at { 1.day.from_now.change(hour: 17, min: 0) }
    slot_duration_minutes { 20 }
  end

  factory :appointment_slot do
    practice
    clinician { association(:staff_member, practice: practice) }
    availability_block { association(:availability_block, practice: practice, clinician: clinician) }
    starts_at { 1.day.from_now.change(hour: 10, min: 0) }
    ends_at { 1.day.from_now.change(hour: 10, min: 20) }
  end

  factory :appointment_hold do
    appointment_slot
    patient { association(:patient, practice: appointment_slot.practice) }
    expires_at { 15.minutes.from_now }
  end

  factory :appointment do
    practice
    clinician { association(:staff_member, practice: practice) }
    patient { association(:patient, practice: practice) }
    appointment_slot { association(:appointment_slot, practice: practice, clinician: clinician) }
    status { "booked" }
    booked_at { Time.current }
  end

  factory :appointment_status_change do
    appointment
    changed_by { association(:user) }
    from_status { "booked" }
    to_status { "confirmed" }
  end

  factory :encounter do
    practice
    patient { association(:patient, practice: practice) }
    clinician { association(:staff_member, practice: practice) }
    encounter_type { "consultation" }
    started_at { Time.current }
  end

  factory :clinical_note do
    patient
    encounter { association(:encounter, practice: patient.practice, patient: patient) }
    author { association(:staff_member, practice: patient.practice) }
    note_type { "general" }
    body { "Patient presented with mild symptoms." }
  end

  factory :payment do
    appointment
    patient { appointment.patient }
    provider { "stripe" }
    currency { "GBP" }
    amount_cents { 5000 }
    sequence(:idempotency_key) { |n| "payment-#{n}" }
    status { "pending" }
  end

  factory :refund do
    payment
    amount_cents { 2500 }
    currency { "GBP" }
    requested_at { Time.current }
    status { "pending" }
  end

  factory :audit_event do
    practice
    auditable { association(:patient, practice: practice) }
    action { "patient.updated" }
  end
end
