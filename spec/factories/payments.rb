FactoryBot.define do
  factory :payment do
    appointment
    patient { appointment.patient }
    provider { "stripe" }
    currency { "GBP" }
    amount_cents { 5000 }
    sequence(:idempotency_key) { |n| "payment-#{n}" }
    status { "pending" }
  end
end
