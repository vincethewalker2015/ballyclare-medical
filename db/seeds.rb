# frozen_string_literal: true

# Demo accounts are opt-in and must never be loaded into a database with real patient data.
unless ENV["DEMO_SEEDS"] == "true"
  puts "Skipping demo seeds. Set DEMO_SEEDS=true to create demo accounts."
  return
end

practice = Practice.find_or_initialize_by(name: "Ballyclare Medical Demo")
practice.assign_attributes(timezone: "Europe/London", currency: "GBP", country_code: "GB", active: true)
practice.save!

accounts = [
  { email: "senior.admin@example.com", first_name: "Alex", last_name: "Morgan", staff_type: "administrator", access_level: "senior_staff_admin" },
  { email: "staff.admin@example.com", first_name: "Sam", last_name: "Taylor", staff_type: "administrator", access_level: "staff_admin" },
  { email: "clinician@example.com", first_name: "Jamie", last_name: "Patel", staff_type: "doctor", access_level: "staff_clinician" },
  { email: "staff@example.com", first_name: "Casey", last_name: "Wilson", staff_type: "administrator", access_level: "staff" }
]

accounts.each do |attributes|
  user = User.find_or_initialize_by(email: attributes.fetch(:email))
  if user.new_record?
    user.password = "Password"
    user.password_confirmation = "Password"
    user.save!
  end

  staff = StaffMember.find_or_initialize_by(practice: practice, user: user)
  staff.assign_attributes(
    first_name: attributes.fetch(:first_name),
    last_name: attributes.fetch(:last_name),
    staff_type: attributes.fetch(:staff_type),
    access_level: attributes.fetch(:access_level),
    active: true
  )
  staff.save!
  puts "Demo account ready: #{attributes.fetch(:email)} (#{attributes.fetch(:access_level)})"
end

puts "Demo accounts seeded. New accounts use the password: Password"
puts "Existing account passwords have not been changed."
