class AddChiefOfGroupToMedicalGroups < ActiveRecord::Migration[8.1]
  def change
    add_reference :medical_groups, :chief_of_group, type: :uuid,
      foreign_key: { to_table: :users }, index: { unique: true }
  end
end
