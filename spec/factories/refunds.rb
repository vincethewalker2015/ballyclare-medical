FactoryBot.define do
  factory :refund do
    payment

    amount_cents { 1000 }
    currency { payment.currency }
    status { "pending" }
    requested_at { Time.current }
    idempotency_key { SecureRandom.uuid }
  end
end
