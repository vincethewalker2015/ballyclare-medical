class CreatePatientAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :patient_accounts, id: :uuid do |t|
      t.string :email, null: false, default: ""
      t.string :encrypted_password, null: false, default: ""
      t.string :reset_password_token
      t.datetime :reset_password_sent_at
      t.datetime :remember_created_at
      t.string :confirmation_token
      t.datetime :confirmed_at
      t.datetime :confirmation_sent_at
      t.string :unconfirmed_email

      t.timestamps null: false
    end

    add_index :patient_accounts, :email, unique: true
    add_index :patient_accounts, :reset_password_token, unique: true
    add_index :patient_accounts, :confirmation_token, unique: true
  end
end
