class CreateAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_events, id: :uuid do |t|
      t.references :user,
        type: :uuid,
        null: true,
        foreign_key: true,
        index: false

      t.references :practice,
        type: :uuid,
        null: false,
        foreign_key: true,
        index: false

      t.string :action, null: false

      t.string :auditable_type, null: false
      t.uuid :auditable_id, null: false

      t.jsonb :metadata,
        null: false,
        default: {}

      t.string :ip_address
      t.text :user_agent

      t.timestamps
    end

    add_index :audit_events,
      [ :auditable_type, :auditable_id, :created_at ]

    add_index :audit_events,
      [ :user_id, :created_at ]

    add_index :audit_events,
      [ :practice_id, :created_at ]

    add_index :audit_events,
      [ :action, :created_at ]
  end
end
