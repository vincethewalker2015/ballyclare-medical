class CreateStaffMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :staff_members, id: :uuid do |t|
      t.references :practice, null: false, foreign_key: true, type: :uuid
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :staff_type, null: false
      t.string :registration_number
      t.integer :default_appointment_duration, null: false, default: 20
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :staff_members, [ :practice_id, :user_id ], unique: true
    add_index :staff_members, [ :practice_id, :staff_type, :active ]
    add_index :staff_members, [ :practice_id, :registration_number ], unique: true, where: "registration_number IS NOT NULL"
    add_check_constraint :staff_members, "staff_type IN ('doctor', 'nurse', 'administrator')", name: "staff_members_appointment_duration_must_be_positive"
  end
end
