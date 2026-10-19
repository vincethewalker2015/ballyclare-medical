FactoryBot.define do
  factory :staff_member do
    practice
    user
    staff_type { "doctor" }
  end
end
