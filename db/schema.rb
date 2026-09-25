# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_25_140103) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "appointment_holds", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "appointment_slot_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.uuid "patient_id", null: false
    t.datetime "updated_at", null: false
    t.index ["appointment_slot_id"], name: "index_appointment_holds_on_appointment_slot_id", unique: true
    t.index ["expires_at"], name: "index_appointment_holds_on_expires_at"
    t.index ["patient_id", "expires_at"], name: "index_appointment_holds_on_patient_id_and_expires_at"
    t.index ["patient_id"], name: "index_appointment_holds_on_patient_id"
  end

  create_table "appointment_slots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "availability_block_id", null: false
    t.uuid "clinician_id", null: false
    t.datetime "created_at", null: false
    t.datetime "ends_at", null: false
    t.uuid "practice_id", null: false
    t.datetime "starts_at", null: false
    t.datetime "updated_at", null: false
    t.index ["availability_block_id", "starts_at"], name: "index_appointment_slots_on_availability_block_id_and_starts_at"
    t.index ["availability_block_id"], name: "index_appointment_slots_on_availability_block_id"
    t.index ["clinician_id", "starts_at"], name: "index_appointment_slots_on_clinician_id_and_starts_at", unique: true
    t.index ["clinician_id"], name: "index_appointment_slots_on_clinician_id"
    t.index ["practice_id", "starts_at"], name: "index_appointment_slots_on_practice_id_and_starts_at"
    t.index ["practice_id"], name: "index_appointment_slots_on_practice_id"
    t.check_constraint "ends_at > starts_at", name: "appointment_slots_end_must_be_after_start"
  end

  create_table "appointment_status_changes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "appointment_id", null: false
    t.uuid "changed_by_id", null: false
    t.datetime "created_at", null: false
    t.string "from_status"
    t.text "notes"
    t.string "to_status", null: false
    t.datetime "updated_at", null: false
    t.index ["appointment_id", "created_at"], name: "idx_on_appointment_id_created_at_f9449d8aae"
    t.index ["appointment_id"], name: "index_appointment_status_changes_on_appointment_id"
    t.index ["changed_by_id", "created_at"], name: "idx_on_changed_by_id_created_at_4bae329a6f"
    t.index ["changed_by_id"], name: "index_appointment_status_changes_on_changed_by_id"
  end

  create_table "appointments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "appointment_slot_id", null: false
    t.datetime "arrived_at"
    t.datetime "booked_at", null: false
    t.text "cancellation_reason"
    t.datetime "cancelled_at"
    t.uuid "cancelled_by_id"
    t.uuid "clinician_id", null: false
    t.datetime "completed_at"
    t.datetime "confirmed_at"
    t.datetime "consultation_started_at"
    t.datetime "created_at", null: false
    t.uuid "patient_id", null: false
    t.text "patient_notes"
    t.uuid "practice_id", null: false
    t.text "reason"
    t.string "status", default: "booked", null: false
    t.datetime "updated_at", null: false
    t.index ["appointment_slot_id"], name: "index_appointments_on_appointment_slot_id", unique: true
    t.index ["cancelled_by_id"], name: "index_appointments_on_cancelled_by_id"
    t.index ["clinician_id", "booked_at"], name: "index_appointments_on_clinician_id_and_booked_at"
    t.index ["clinician_id", "status", "booked_at"], name: "index_appointments_on_clinician_id_and_status_and_booked_at"
    t.index ["clinician_id"], name: "index_appointments_on_clinician_id"
    t.index ["patient_id", "booked_at"], name: "index_appointments_on_patient_id_and_booked_at"
    t.index ["patient_id"], name: "index_appointments_on_patient_id"
    t.index ["practice_id", "status", "booked_at"], name: "index_appointments_on_practice_id_and_status_and_booked_at"
    t.index ["practice_id"], name: "index_appointments_on_practice_id"
  end

  create_table "audit_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.uuid "auditable_id", null: false
    t.string "auditable_type", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.jsonb "metadata", default: {}, null: false
    t.uuid "practice_id", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.uuid "user_id"
    t.index ["action", "created_at"], name: "index_audit_events_on_action_and_created_at"
    t.index ["auditable_type", "auditable_id", "created_at"], name: "idx_on_auditable_type_auditable_id_created_at_912ae734ed"
    t.index ["practice_id", "created_at"], name: "index_audit_events_on_practice_id_and_created_at"
    t.index ["user_id", "created_at"], name: "index_audit_events_on_user_id_and_created_at"
  end

  create_table "availability_blocks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "bookable_online", default: true, null: false
    t.uuid "clinician_id", null: false
    t.datetime "created_at", null: false
    t.datetime "ends_at", null: false
    t.uuid "practice_id", null: false
    t.integer "slot_duration_minutes", default: 20, null: false
    t.datetime "starts_at", null: false
    t.datetime "updated_at", null: false
    t.index ["clinician_id", "starts_at"], name: "index_availability_blocks_on_clinician_id_and_starts_at"
    t.index ["clinician_id"], name: "index_availability_blocks_on_clinician_id"
    t.index ["practice_id", "starts_at"], name: "index_availability_blocks_on_practice_id_and_starts_at"
    t.index ["practice_id"], name: "index_availability_blocks_on_practice_id"
    t.check_constraint "ends_at > starts_at", name: "availability_blocks_end_must_be_after_start"
    t.check_constraint "slot_duration_minutes > 0", name: "availability_blocks_slot_duration_must_be_positive"
  end

  create_table "clinical_notes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "author_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.uuid "encounter_id", null: false
    t.string "note_type", null: false
    t.uuid "patient_id", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id", "created_at"], name: "index_clinical_notes_on_author_id_and_created_at"
    t.index ["author_id"], name: "index_clinical_notes_on_author_id"
    t.index ["encounter_id", "created_at"], name: "index_clinical_notes_on_encounter_id_and_created_at"
    t.index ["encounter_id"], name: "index_clinical_notes_on_encounter_id"
    t.index ["patient_id", "created_at"], name: "index_clinical_notes_on_patient_id_and_created_at"
    t.index ["patient_id"], name: "index_clinical_notes_on_patient_id"
  end

  create_table "encounters", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "appointment_id"
    t.uuid "clinician_id", null: false
    t.datetime "created_at", null: false
    t.string "encounter_type", null: false
    t.datetime "ended_at"
    t.uuid "patient_id", null: false
    t.uuid "practice_id", null: false
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
    t.index ["appointment_id"], name: "index_encounters_on_appointment_id", unique: true, where: "(appointment_id IS NOT NULL)"
    t.index ["clinician_id", "created_at"], name: "index_encounters_on_clinician_id_and_created_at"
    t.index ["clinician_id"], name: "index_encounters_on_clinician_id"
    t.index ["patient_id", "created_at"], name: "index_encounters_on_patient_id_and_created_at"
    t.index ["patient_id"], name: "index_encounters_on_patient_id"
    t.index ["practice_id", "created_at"], name: "index_encounters_on_practice_id_and_created_at"
    t.index ["practice_id"], name: "index_encounters_on_practice_id"
    t.check_constraint "ended_at IS NULL OR ended_at >= started_at", name: "encounters_end_must_not_be_before_start"
  end

  create_table "patient_identifiers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "country_code"
    t.datetime "created_at", null: false
    t.string "identifier_type", null: false
    t.string "identifier_value", null: false
    t.string "issuing_authority"
    t.uuid "patient_id", null: false
    t.datetime "updated_at", null: false
    t.index ["identifier_type", "identifier_value"], name: "idx_on_identifier_type_identifier_value_cd539bf894"
    t.index ["patient_id", "identifier_type", "identifier_value"], name: "index_patient_identifiers_on_patient_type_and_value", unique: true
  end

  create_table "patients", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "address_line_1"
    t.string "address_line_2"
    t.string "city"
    t.string "country_code"
    t.string "county"
    t.datetime "created_at", null: false
    t.date "date_of_birth", null: false
    t.string "email"
    t.string "first_name", null: false
    t.string "gender_identity"
    t.string "last_name", null: false
    t.string "middle_names"
    t.string "patient_number", null: false
    t.string "phone"
    t.string "postcode"
    t.uuid "practice_id", null: false
    t.string "sex_at_birth"
    t.string "title"
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["practice_id", "last_name", "date_of_birth"], name: "index_patients_on_practice_id_and_last_name_and_date_of_birth"
    t.index ["practice_id", "patient_number"], name: "index_patients_on_practice_id_and_patient_number", unique: true
    t.index ["practice_id"], name: "index_patients_on_practice_id"
    t.index ["user_id"], name: "index_patients_on_user_id", unique: true, where: "(user_id IS NOT NULL)"
  end

  create_table "payments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.uuid "appointment_hold_id"
    t.uuid "appointment_id"
    t.string "card_brand"
    t.string "card_last_four"
    t.datetime "created_at", null: false
    t.string "currency", null: false
    t.datetime "failed_at"
    t.string "idempotency_key", null: false
    t.datetime "paid_at"
    t.uuid "patient_id", null: false
    t.string "payment_method_type"
    t.string "provider", null: false
    t.string "provider_charge_id"
    t.jsonb "provider_data", default: {}, null: false
    t.string "provider_payment_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["appointment_hold_id"], name: "index_payments_on_appointment_hold_id"
    t.index ["appointment_id", "created_at"], name: "index_payments_on_appointment_id_and_created_at"
    t.index ["idempotency_key"], name: "index_payments_on_idempotency_key", unique: true
    t.index ["patient_id", "created_at"], name: "index_payments_on_patient_id_and_created_at"
    t.index ["provider", "provider_payment_id"], name: "index_payments_on_provider_and_provider_payment_id", unique: true, where: "(provider_payment_id IS NOT NULL)"
    t.index ["status", "created_at"], name: "index_payments_on_status_and_created_at"
    t.check_constraint "amount_cents > 0", name: "payments_amount_must_be_positive"
  end

  create_table "practices", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "address_line_1"
    t.string "address_line_2"
    t.string "city"
    t.string "country_code", null: false
    t.datetime "created_at", null: false
    t.string "currency", null: false
    t.string "email"
    t.string "name", null: false
    t.string "phone"
    t.string "postal_code"
    t.string "region"
    t.string "timezone", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_practices_on_name", unique: true
  end

  create_table "refunds", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "currency", null: false
    t.text "failure_reason"
    t.uuid "payment_id", null: false
    t.jsonb "provider_data", default: {}, null: false
    t.string "provider_refund_id"
    t.string "reason"
    t.datetime "refunded_at"
    t.datetime "requested_at", null: false
    t.uuid "requested_by_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["payment_id", "created_at"], name: "index_refunds_on_payment_id_and_created_at"
    t.index ["provider_refund_id"], name: "index_refunds_on_provider_refund_id", unique: true, where: "(provider_refund_id IS NOT NULL)"
    t.index ["requested_by_id"], name: "index_refunds_on_requested_by_id"
    t.index ["status", "created_at"], name: "index_refunds_on_status_and_created_at"
    t.check_constraint "amount_cents > 0", name: "refunds_amount_must_be_positive"
    t.check_constraint "currency::text <> ''::text", name: "refunds_currency_must_not_be_empty"
  end

  create_table "roles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_roles_on_name", unique: true
  end

  create_table "staff_members", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.integer "default_appointment_duration", default: 20, null: false
    t.uuid "practice_id", null: false
    t.string "registration_number"
    t.string "staff_type", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["practice_id", "registration_number"], name: "index_staff_members_on_practice_id_and_registration_number", unique: true, where: "(registration_number IS NOT NULL)"
    t.index ["practice_id", "staff_type", "active"], name: "index_staff_members_on_practice_id_and_staff_type_and_active"
    t.index ["practice_id", "user_id"], name: "index_staff_members_on_practice_id_and_user_id", unique: true
    t.index ["practice_id"], name: "index_staff_members_on_practice_id"
    t.index ["user_id"], name: "index_staff_members_on_user_id"
    t.check_constraint "staff_type::text = ANY (ARRAY['doctor'::character varying, 'nurse'::character varying, 'administrator'::character varying]::text[])", name: "staff_members_appointment_duration_must_be_positive"
  end

  create_table "user_roles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "role_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["role_id"], name: "index_user_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_user_roles_on_user_id_and_role_id", unique: true
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "appointment_holds", "appointment_slots"
  add_foreign_key "appointment_holds", "patients"
  add_foreign_key "appointment_slots", "availability_blocks"
  add_foreign_key "appointment_slots", "practices"
  add_foreign_key "appointment_slots", "staff_members", column: "clinician_id"
  add_foreign_key "appointment_status_changes", "appointments"
  add_foreign_key "appointment_status_changes", "users", column: "changed_by_id"
  add_foreign_key "appointments", "appointment_slots"
  add_foreign_key "appointments", "patients"
  add_foreign_key "appointments", "practices"
  add_foreign_key "appointments", "staff_members", column: "clinician_id"
  add_foreign_key "appointments", "users", column: "cancelled_by_id"
  add_foreign_key "audit_events", "practices"
  add_foreign_key "audit_events", "users"
  add_foreign_key "availability_blocks", "practices"
  add_foreign_key "availability_blocks", "staff_members", column: "clinician_id"
  add_foreign_key "clinical_notes", "encounters"
  add_foreign_key "clinical_notes", "patients"
  add_foreign_key "clinical_notes", "staff_members", column: "author_id"
  add_foreign_key "encounters", "appointments"
  add_foreign_key "encounters", "patients"
  add_foreign_key "encounters", "practices"
  add_foreign_key "encounters", "staff_members", column: "clinician_id"
  add_foreign_key "patient_identifiers", "patients"
  add_foreign_key "patients", "practices"
  add_foreign_key "patients", "users"
  add_foreign_key "payments", "appointment_holds"
  add_foreign_key "payments", "appointments"
  add_foreign_key "payments", "patients"
  add_foreign_key "refunds", "payments"
  add_foreign_key "refunds", "users", column: "requested_by_id"
  add_foreign_key "staff_members", "practices"
  add_foreign_key "staff_members", "users"
  add_foreign_key "user_roles", "roles"
  add_foreign_key "user_roles", "users"
end
