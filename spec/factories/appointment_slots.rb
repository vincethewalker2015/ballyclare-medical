FactoryBot.define do
  factory :appointment_slot do
    practice
    clinician { association(:staff_member, practice: practice) }
    availability_block { association(:availability_block, practice: practice, clinician: clinician) }
    starts_at { 1.day.from_now.change(hour: 10, min: 0) }
    ends_at { 1.day.from_now.change(hour: 10, min: 20) }
  end
end
