FactoryBot.define do
  factory :patient do
    practice
    sequence(:patient_number) { |n| "P#{n.to_s.rjust(6, "0")}" }
    first_name { "Jane" }
    last_name { "Doe" }
    date_of_birth { Date.new(1990, 1, 1) }
  end

  factory :patient_identifier do
    patient
    identifier_type { "nhs_number" }
    sequence(:identifier_value) { |n| format("%010d", n) }
  end
end
