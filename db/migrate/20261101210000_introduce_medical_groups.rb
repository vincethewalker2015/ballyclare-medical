class IntroduceMedicalGroups < ActiveRecord::Migration[8.1]
  def up
    create_table :medical_groups, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.timestamps
    end

    add_reference :practices, :medical_group, type: :uuid,
      null: true, index: true, foreign_key: true

    # Keep every existing practice isolated until group membership is approved.
    execute <<~SQL
      INSERT INTO medical_groups (id, name, created_at, updated_at)
      SELECT id, name, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM practices
    SQL

    execute "UPDATE practices SET medical_group_id = id"
    change_column_null :practices, :medical_group_id, false
  end

  def down
    remove_reference :practices, :medical_group, foreign_key: true, index: true
    drop_table :medical_groups
  end
end
