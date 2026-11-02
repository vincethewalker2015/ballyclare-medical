class AddSignedAtToClinicalNotes < ActiveRecord::Migration[8.0]
  def change
    add_column :clinical_notes, :signed_at, :datetime
    # Pre-existing records were already treated as signed before draft support.
    reversible do |direction|
      direction.up do
        execute "UPDATE clinical_notes SET signed_at = created_at WHERE status = 'signed'"
      end
    end
  end
end
