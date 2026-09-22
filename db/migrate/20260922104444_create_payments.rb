class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments, id: :uuid do |t|
      t.references :appointment,
        type: :uuid,
        null: false,
        foreign_key: true,
        index: false

      t.references :patient,
        type: :uuid,
        null: false,
        foreign_key: true,
        index: false

      t.string :provider, null: false
      t.string :provider_payment_id
      t.string :provider_charge_id

      t.integer :amount_cents, null: false
      t.string :currency, null: false

      t.string :status,
        null: false,
        default: "pending"

      t.string :payment_method_type
      t.string :card_brand
      t.string :card_last_four

      t.string :idempotency_key, null: false

      t.datetime :paid_at
      t.datetime :failed_at

      t.jsonb :provider_data,
        null: false,
        default: {}

      t.timestamps
    end

    add_index :payments,
      :idempotency_key,
      unique: true

    add_index :payments,
      [ :provider, :provider_payment_id ],
      unique: true,
      where: "provider_payment_id IS NOT NULL"

    add_index :payments,
      [ :appointment_id, :created_at ]

    add_index :payments,
      [ :patient_id, :created_at ]

    add_index :payments,
      [ :status, :created_at ]

    add_check_constraint :payments,
      "amount_cents > 0",
      name: "payments_amount_must_be_positive"
  end
end
