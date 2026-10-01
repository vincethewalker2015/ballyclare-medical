FactoryBot.define do
  factory :staff_member do
    practice
    user
    staff_type { "doctor" }
    default_appointment_duration { 20 }
  end
end
