FactoryBot.define do
  factory :staff_member do
    practice
    user
    staff_type { "doctor" }
    first_name { "Alex" }
    last_name { "Morgan" }
  end
end
