class CreateGuestBookings < ActiveRecord::Migration[8.1]
  def change
    create_table :guest_bookings, id: :uuid do |t|
      t.references :practice, type: :uuid, null: false, foreign_key: true
      t.references :appointment_slot, type: :uuid, null: false, foreign_key: true
      t.references :patient, type: :uuid, foreign_key: true
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.date :date_of_birth, null: false
      t.string :email, null: false
      t.string :phone, null: false
      t.text :consultation_reason, null: false
      t.string :status, null: false, default: "draft"
      t.datetime :expires_at, null: false
      t.timestamps
    end

    add_index :guest_bookings, [ :appointment_slot_id, :status ]
    add_index :guest_bookings, :expires_at
  end
end
