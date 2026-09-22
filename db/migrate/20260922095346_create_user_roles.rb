class CreateUserRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :user_roles, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid, index: false
      t.references :role, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
    add_index :user_roles, [ :user_id, :role_id ], unique: true
  end
end
