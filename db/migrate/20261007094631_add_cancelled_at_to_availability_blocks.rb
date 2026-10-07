class AddCancelledAtToAvailabilityBlocks < ActiveRecord::Migration[8.1]
  def change
    add_column :availability_blocks, :cancelled_at, :datetime
  end
end
