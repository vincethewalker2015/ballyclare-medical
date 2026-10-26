class PrepareGuestPaymentBookings < ActiveRecord::Migration[8.1]
  def change
    add_column :patients, :patient_type, :string, default: "practice", null: false
    add_check_constraint :patients, "patient_type IN ('practice', 'external')",
      name: "patients_patient_type_valid"

    add_reference :appointment_holds, :guest_booking, type: :uuid,
      foreign_key: true, index: { unique: true }
    change_column_null :appointment_holds, :patient_id, true
    add_check_constraint :appointment_holds,
      "(patient_id IS NOT NULL AND guest_booking_id IS NULL) OR (patient_id IS NULL AND guest_booking_id IS NOT NULL)",
      name: "appointment_holds_exactly_one_booking_owner"

    add_reference :payments, :guest_booking, type: :uuid,
      foreign_key: true, index: { unique: true }
    change_column_null :payments, :patient_id, true
    add_check_constraint :payments,
      "patient_id IS NOT NULL OR guest_booking_id IS NOT NULL",
      name: "payments_booking_owner_present"
  end
end
