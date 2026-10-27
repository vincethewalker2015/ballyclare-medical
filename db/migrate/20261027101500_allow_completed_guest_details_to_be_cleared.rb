class AllowCompletedGuestDetailsToBeCleared < ActiveRecord::Migration[8.1]
  def change
    %i[first_name last_name date_of_birth email phone consultation_reason].each do |column|
      change_column_null :guest_bookings, column, true
    end
  end
end
