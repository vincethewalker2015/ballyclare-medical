class AllowHistoricalAppointmentHolds < ActiveRecord::Migration[8.1]
  def change
    remove_index :appointment_holds,
                 :appointment_slot_id,
                 unique: true

    add_index :appointment_holds,
              [ :appointment_slot_id, :expires_at ],
              name: "index_appointment_holds_on_slot_and_expires_at"
  end
end
