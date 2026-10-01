FactoryBot.define do
  factory :appointment_charge do
    appointment
    patient { appointment.patient }
    practice { appointment.practice }
    description { "Consultation fee" }
    charge_type { "appointment" }
    amount_cents { 5000 }
    currency { appointment.practice.currency }
    status { "active" }
    charged_at { Time.current }
  end
end
