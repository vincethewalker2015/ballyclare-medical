FactoryBot.define do
  factory :appointment_status_change do
    appointment
    changed_by { association(:user) }
    from_status { "booked" }
    to_status { "confirmed" }
  end
end
