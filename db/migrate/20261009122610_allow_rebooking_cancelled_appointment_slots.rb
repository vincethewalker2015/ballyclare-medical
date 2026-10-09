class AllowRebookingCancelledAppointmentSlots < ActiveRecord::Migration[8.1]
  def change
    remove_index :appointments, name: "index_appointments_on_appointment_slot_id"

    add_index :appointments,
              :appointment_slot_id,
              unique: true,
              where: "status <> 'cancelled'",
              name: "index_appointments_on_active_appointment_slot_id"
  end
end
