class AddPrintableToClinicalDocumentReleases < ActiveRecord::Migration[8.1]
  def change
    add_column :clinical_document_releases, :printable, :boolean, default: false, null: false
  end
end