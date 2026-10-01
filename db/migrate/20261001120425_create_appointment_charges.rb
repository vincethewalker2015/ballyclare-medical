class CreateAppointmentCharges < ActiveRecord::Migration[8.1]
  def change
    create_table :appointment_charges, id: :uuid do |t|
      t.references :appointment,
                   null: false,
                   foreign_key: true,
                   type: :uuid

      t.references :patient,
                   null: false,
                   foreign_key: true,
                   type: :uuid

      t.references :practice,
                   null: false,
                   foreign_key: true,
                   type: :uuid

      t.references :created_by,
                   null: true,
                   foreign_key: { to_table: :users },
                   type: :uuid

      t.string :description, null: false
      t.string :charge_type, null: false
      t.integer :amount_cents, null: false
      t.string :currency, null: false
      t.string :status, null: false, default: "active"
      t.datetime :charged_at, null: false

      t.timestamps
    end

    add_index :appointment_charges,
              [ :appointment_id, :charged_at ]

    add_index :appointment_charges,
              [ :patient_id, :charged_at ]

    add_index :appointment_charges,
              [ :practice_id, :charged_at ]

    add_check_constraint :appointment_charges,
                         "amount_cents > 0",
                         name: "appointment_charges_amount_must_be_positive"

    add_check_constraint :appointment_charges,
                         "currency <> ''",
                         name: "appointment_charges_currency_must_not_be_empty"

    add_check_constraint :appointment_charges,
                         "status IN ('active', 'voided')",
                         name: "appointment_charges_status_must_be_valid"

    add_check_constraint :appointment_charges,
                         "charge_type IN ('appointment', 'additional')",
                         name: "appointment_charges_type_must_be_valid"
  end
end
