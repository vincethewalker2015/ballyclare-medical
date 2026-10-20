class AddInvitationPendingAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :invitation_pending_at, :datetime
  end
end
