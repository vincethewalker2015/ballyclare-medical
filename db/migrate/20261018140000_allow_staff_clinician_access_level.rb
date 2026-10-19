class AllowStaffClinicianAccessLevel < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :staff_members, name: "staff_members_access_level_allowed"

    add_check_constraint :staff_members,
      "access_level IN ('staff', 'staff_clinician', 'staff_admin', 'senior_staff_admin')",
      name: "staff_members_access_level_allowed"
  end
end
