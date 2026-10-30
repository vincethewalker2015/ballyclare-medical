class AllowPatientInitiatedAppointmentStatusChanges < ActiveRecord::Migration[8.0]
  def change
    change_column_null :appointment_status_changes, :changed_by_id, true
  end
end
