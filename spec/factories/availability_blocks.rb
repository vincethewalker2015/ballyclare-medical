FactoryBot.define do
  factory :availability_block do
    practice
    clinician { association(:staff_member, practice: practice) }
    starts_at { 1.day.from_now.change(hour: 9, min: 0) }
    ends_at { 1.day.from_now.change(hour: 17, min: 0) }
    slot_duration_minutes { 20 }
  end
end
