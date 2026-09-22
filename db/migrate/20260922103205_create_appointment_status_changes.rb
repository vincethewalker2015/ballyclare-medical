class CreateAppointmentStatusChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :appointment_status_changes, id: :uuid do |t|
      t.references :appointment,
        type: :uuid,
        null: false,
        foreign_key: true

      t.references :changed_by,
        type: :uuid,
        null: false,
        foreign_key: { to_table: :users }

      t.string :from_status
      t.string :to_status, null: false

      t.text :notes

      t.timestamps
    end

    add_index :appointment_status_changes,
      [ :appointment_id, :created_at ]

    add_index :appointment_status_changes,
      [ :changed_by_id, :created_at ]
  end
end
