class CreateAppointmentHolds < ActiveRecord::Migration[8.1]
  def change
    create_table :appointment_holds, id: :uuid do |t|
      t.references :appointment_slot,
        type: :uuid,
        null: false,
        foreign_key: true,
        index: false

      t.references :patient,
        type: :uuid,
        null: false,
        foreign_key: true

      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :appointment_holds,
      :appointment_slot_id,
      unique: true

    add_index :appointment_holds,
      :expires_at

    add_index :appointment_holds,
      [ :patient_id, :expires_at ]
  end
end
