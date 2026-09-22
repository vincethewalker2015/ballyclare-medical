class CreateRefunds < ActiveRecord::Migration[8.1]
  def change
    create_table :refunds, id: :uuid do |t|
      t.references :payment,
        type: :uuid,
        null: false,
        foreign_key: true,
        index: false

      t.references :requested_by,
        type: :uuid,
        null: true,
        foreign_key: { to_table: :users }

      # Provider's identifier for this refund
      t.string :provider_refund_id

      # Money
      t.integer :amount_cents, null: false
      t.string :currency, null: false

      # Refund lifecycle
      t.string :status,
        null: false,
        default: "pending"

      t.string :reason
      t.text :failure_reason

      t.datetime :requested_at, null: false
      t.datetime :refunded_at

      # Non-sensitive provider-specific information
      t.jsonb :provider_data,
        null: false,
        default: {}

      t.timestamps
    end

    add_index :refunds,
      [ :payment_id, :created_at ]

    add_index :refunds,
      :provider_refund_id,
      unique: true,
      where: "provider_refund_id IS NOT NULL"

    add_index :refunds,
      [ :status, :created_at ]

    add_check_constraint :refunds,
      "amount_cents > 0",
      name: "refunds_amount_must_be_positive"

    add_check_constraint :refunds,
      "currency <> ''",
      name: "refunds_currency_must_not_be_empty"
  end
end
