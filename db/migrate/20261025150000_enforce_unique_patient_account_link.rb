class EnforceUniquePatientAccountLink < ActiveRecord::Migration[8.1]
  def change
    remove_index :patient_account_links,
      name: "index_patient_account_links_on_practice_and_account"
    add_index :patient_account_links, :patient_account_id,
      unique: true, name: "index_patient_account_links_on_account_unique"
  end
end
