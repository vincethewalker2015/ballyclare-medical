FactoryBot.define do
  factory :patient_account do
    sequence(:email) { |n| "patient_account#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }
  end
end
