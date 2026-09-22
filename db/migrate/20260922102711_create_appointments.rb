class CreateAppointments < ActiveRecord::Migration[8.1]
  def change
    create_table :appointments, id: :uuid do |t|
      t.references :practice,
        type: :uuid,
        null: false,
        foreign_key: true

      t.references :appointment_slot,
        type: :uuid,
        null: false,
        foreign_key: true,
        index: false

      t.references :patient,
        type: :uuid,
        null: false,
        foreign_key: true

      t.references :clinician,
        type: :uuid,
        null: false,
        foreign_key: { to_table: :staff_members }

      t.references :cancelled_by,
        type: :uuid,
        null: true,
        foreign_key: { to_table: :users }

      t.text :reason
      t.text :patient_notes

      t.string :status,
        null: false,
        default: "booked"

      t.datetime :booked_at, null: false
      t.datetime :confirmed_at
      t.datetime :arrived_at
      t.datetime :consultation_started_at
      t.datetime :completed_at
      t.datetime :cancelled_at

      t.text :cancellation_reason

      t.timestamps
    end

    add_index :appointments,
      :appointment_slot_id,
      unique: true

    add_index :appointments,
      [ :patient_id, :booked_at ]

    add_index :appointments,
      [ :clinician_id, :booked_at ]

    add_index :appointments,
      [ :clinician_id, :status, :booked_at ]

    add_index :appointments,
      [ :practice_id, :status, :booked_at ]
  end
end
