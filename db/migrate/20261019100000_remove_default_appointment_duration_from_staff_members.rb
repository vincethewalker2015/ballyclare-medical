class RemoveDefaultAppointmentDurationFromStaffMembers < ActiveRecord::Migration[8.1]
  def change
    remove_column :staff_members, :default_appointment_duration, :integer
  end
end
