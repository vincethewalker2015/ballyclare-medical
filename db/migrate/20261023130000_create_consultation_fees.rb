class CreateConsultationFees < ActiveRecord::Migration[8.1]
  def change
    create_table :consultation_fees, id: :uuid do |t|
      t.references :practice, type: :uuid, null: false, foreign_key: true
      t.string :clinician_type, null: false
      t.integer :amount_cents, null: false
      t.string :currency, null: false
      t.timestamps
    end

    add_index :consultation_fees, [ :practice_id, :clinician_type ], unique: true
    add_check_constraint :consultation_fees, "amount_cents > 0", name: "consultation_fees_positive_amount"
    add_check_constraint :consultation_fees, "clinician_type IN ('doctor', 'nurse')",
      name: "consultation_fees_clinician_type"
  end
end
