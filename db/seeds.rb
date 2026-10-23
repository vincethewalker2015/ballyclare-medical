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
  { email: "doctor@example.com", first_name: "Olivia", last_name: "Carter", staff_type: "doctor", access_level: "staff_clinician" },
  { email: "nurse@example.com", first_name: "Sarah", last_name: "Wilson", staff_type: "doctor", access_level: "staff_clinician" },
  { email: "staff@example.com", first_name: "Ronelle", last_name: "Oosthuizen", staff_type: "administrator", access_level: "staff" }
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

# Fictional demonstration records only. Patient numbers are stable so this
# script can safely run again without creating duplicate patients.
demo_patients = [
  [ "DEMO-P001", "Amelia", "Bennett", "1986-04-18", "Ms" ],
  [ "DEMO-P002", "Oliver", "Clarke", "1974-11-09", "Mr" ],
  [ "DEMO-P003", "Isla", "Campbell", "1995-06-22", "Ms" ],
  [ "DEMO-P004", "Noah", "Hughes", "2002-01-15", "Mr" ],
  [ "DEMO-P005", "Grace", "Mitchell", "1958-08-03", "Mrs" ],
  [ "DEMO-P006", "Leo", "Anderson", "1989-12-27", "Mr" ],
  [ "DEMO-P007", "Freya", "Roberts", "2011-02-14", "Miss" ],
  [ "DEMO-P008", "Arthur", "Evans", "1949-09-05", "Mr" ],
  [ "DEMO-P009", "Sophie", "Turner", "1992-05-30", "Ms" ],
  [ "DEMO-P010", "Henry", "Cooper", "1967-03-12", "Mr" ],
  [ "DEMO-P011", "Ella", "Morgan", "2007-10-21", "Miss" ],
  [ "DEMO-P012", "Jack", "Stewart", "1981-07-08", "Mr" ],
  [ "DEMO-P013", "Ruby", "Wilson", "1979-02-26", "Ms" ],
  [ "DEMO-P014", "Oscar", "Patel", "1998-09-17", "Mr" ],
  [ "DEMO-P015", "Mia", "Thompson", "1963-01-04", "Mrs" ],
  [ "DEMO-P016", "George", "Walker", "1955-12-02", "Mr" ],
  [ "DEMO-P017", "Ava", "Reid", "2017-05-11", "Miss" ],
  [ "DEMO-P018", "Thomas", "Kelly", "1990-06-29", "Mr" ],
  [ "DEMO-P019", "Emily", "Brown", "1983-03-06", "Ms" ],
  [ "DEMO-P020", "Daniel", "Murphy", "1971-11-23", "Mr" ]
]

demo_patients.each do |number, first_name, last_name, birth_date, title|
  patient = practice.patients.find_or_initialize_by(patient_number: number)
  next unless patient.new_record?

  patient.assign_attributes(
    first_name: first_name,
    last_name: last_name,
    date_of_birth: Date.iso8601(birth_date),
    title: title,
    country_code: "GB",
    active: true
  )
  patient.save!
end

puts "Demo patients ready: #{demo_patients.length} fictional patients for #{practice.name}."
