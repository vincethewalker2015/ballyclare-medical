class CreateEncounters < ActiveRecord::Migration[8.1]
  def change
    create_table :encounters, id: :uuid do |t|
      t.references :practice,
        type: :uuid,
        null: false,
        foreign_key: true

      t.references :patient,
        type: :uuid,
        null: false,
        foreign_key: true

      t.references :appointment,
        type: :uuid,
        null: true,
        foreign_key: true,
        index: false

      t.references :clinician,
        type: :uuid,
        null: false,
        foreign_key: { to_table: :staff_members }

      t.string :encounter_type, null: false

      t.datetime :started_at, null: false
      t.datetime :ended_at

      t.timestamps
    end

    add_index :encounters,
      :appointment_id,
      unique: true,
      where: "appointment_id IS NOT NULL"

    add_index :encounters,
      [ :patient_id, :created_at ]

    add_index :encounters,
      [ :clinician_id, :created_at ]

    add_index :encounters,
      [ :practice_id, :created_at ]

    add_check_constraint :encounters,
      "ended_at IS NULL OR ended_at >= started_at",
      name: "encounters_end_must_not_be_before_start"
  end
end
