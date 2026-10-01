FactoryBot.define do
  factory :practice do
    sequence(:name) { |n| "Practice #{n}" }
    timezone { "Europe/London" }
    currency { "GBP" }
    country_code { "GB" }
  end

  factory :audit_event do
    practice
    auditable { association(:patient, practice: practice) }
    action { "patient.updated" }
  end
end
