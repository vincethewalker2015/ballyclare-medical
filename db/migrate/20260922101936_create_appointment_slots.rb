class CreateAppointmentSlots < ActiveRecord::Migration[8.1]
  def change
    create_table :appointment_slots, id: :uuid do |t|
      t.references :practice,
        type: :uuid,
        null: false,
        foreign_key: true

      t.references :clinician,
        type: :uuid,
        null: false,
        foreign_key: { to_table: :staff_members }

      t.references :availability_block,
        type: :uuid,
        null: false,
        foreign_key: true

      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false

      t.timestamps
    end

    add_index :appointment_slots,
      [ :clinician_id, :starts_at ],
      unique: true

    add_index :appointment_slots,
      [ :practice_id, :starts_at ]

    add_index :appointment_slots,
      [ :availability_block_id, :starts_at ]

    add_check_constraint :appointment_slots,
      "ends_at > starts_at",
      name: "appointment_slots_end_must_be_after_start"
  end
end
