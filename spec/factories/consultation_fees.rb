FactoryBot.define do
  factory :consultation_fee do
    practice
    clinician_type { "doctor" }
    amount_cents { 6_500 }
    currency { practice.currency }
  end
end
