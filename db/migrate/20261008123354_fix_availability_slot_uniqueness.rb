class FixAvailabilitySlotUniqueness < ActiveRecord::Migration[8.1]
  def up
    enable_extension "btree_gist" unless extension_enabled?("btree_gist")

    remove_index :appointment_slots,
      name: "index_appointment_slots_on_clinician_id_and_starts_at"

    remove_index :appointment_slots,
      name: "index_appointment_slots_on_availability_block_id_and_starts_at"

    add_index :appointment_slots,
      [ :availability_block_id, :starts_at ],
      unique: true,
      name: "index_appointment_slots_on_block_and_starts_at_unique"

    execute <<~SQL
      ALTER TABLE availability_blocks
      ADD CONSTRAINT no_overlapping_active_availability
      EXCLUDE USING gist (
        clinician_id WITH =,
        tsrange(starts_at, ends_at, '[)') WITH &&
      )
      WHERE (cancelled_at IS NULL);
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE availability_blocks
      DROP CONSTRAINT no_overlapping_active_availability;
    SQL

    remove_index :appointment_slots,
      name: "index_appointment_slots_on_block_and_starts_at_unique"

    add_index :appointment_slots,
      [ :availability_block_id, :starts_at ],
      name: "index_appointment_slots_on_availability_block_id_and_starts_at"

    add_index :appointment_slots,
      [ :clinician_id, :starts_at ],
      unique: true,
      name: "index_appointment_slots_on_clinician_id_and_starts_at"
  end
end
