class AllowPaymentsWithoutAppointment < ActiveRecord::Migration[8.1]
  def change
    change_column_null :payments, :appointment_id, true

    add_reference :payments,
                  :appointment_hold,
                  type: :uuid,
                  null: true,
                  foreign_key: true
  end
end
