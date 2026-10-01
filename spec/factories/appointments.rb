FactoryBot.define do
  factory :appointment do
    practice
    clinician { association(:staff_member, practice: practice) }
    patient { association(:patient, practice: practice) }
    appointment_slot { association(:appointment_slot, practice: practice, clinician: clinician) }
    status { "booked" }
    booked_at { Time.current }
  end

  factory :encounter do
    practice
    patient { association(:patient, practice: practice) }
    clinician { association(:staff_member, practice: practice) }
    encounter_type { "consultation" }
    started_at { Time.current }
  end

  factory :clinical_note do
    patient
    encounter { association(:encounter, practice: patient.practice, patient: patient) }
    author { association(:staff_member, practice: patient.practice) }
    note_type { "general" }
    body { "Patient presented with mild symptoms." }
  end
end
