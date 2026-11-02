FactoryBot.define do
  factory :medical_group do
    sequence(:name) { |n| "Medical Group #{n}" }
  end
end
