class CreateAvailabilityBlocks < ActiveRecord::Migration[8.1]
  def change
    create_table :availability_blocks, id: :uuid do |t|
      t.references :practice,
        type: :uuid,
        null: false,
        foreign_key: true

      t.references :clinician,
        type: :uuid,
        null: false,
        foreign_key: { to_table: :staff_members }

      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false

      t.integer :slot_duration_minutes,
        null: false,
        default: 20

      t.boolean :bookable_online,
        null: false,
        default: true

      t.timestamps
    end

    add_index :availability_blocks,
      [ :clinician_id, :starts_at ]

    add_index :availability_blocks,
      [ :practice_id, :starts_at ]

    add_check_constraint :availability_blocks,
      "ends_at > starts_at",
      name: "availability_blocks_end_must_be_after_start"

    add_check_constraint :availability_blocks,
      "slot_duration_minutes > 0",
      name: "availability_blocks_slot_duration_must_be_positive"
  end
end
