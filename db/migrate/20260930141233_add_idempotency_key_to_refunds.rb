class AddIdempotencyKeyToRefunds < ActiveRecord::Migration[8.1]
  def change
    add_column :refunds, :idempotency_key, :string, null: false

    add_index :refunds,
              :idempotency_key,
              unique: true
  end
end
