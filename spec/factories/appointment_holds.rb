FactoryBot.define do
  factory :appointment_hold do
    appointment_slot
    patient { association(:patient, practice: appointment_slot.practice) }
    expires_at { 15.minutes.from_now }
  end
end
