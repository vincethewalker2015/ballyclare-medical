class AddAccessLevelToStaffMembers < ActiveRecord::Migration[8.1]
  def change
    add_column :staff_members, :access_level, :string,
      default: "staff", null: false

    add_check_constraint :staff_members,
      "access_level IN ('staff', 'staff_admin', 'senior_staff_admin')",
      name: "staff_members_access_level_allowed"
  end
end
