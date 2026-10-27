class RequireActiveGuestBookingDetails < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :guest_bookings,
      "status = 'completed' OR (first_name IS NOT NULL AND btrim(first_name) <> '' AND last_name IS NOT NULL AND btrim(last_name) <> '' AND date_of_birth IS NOT NULL AND email IS NOT NULL AND btrim(email) <> '' AND phone IS NOT NULL AND btrim(phone) <> '' AND consultation_reason IS NOT NULL AND btrim(consultation_reason) <> '')",
      name: "guest_bookings_active_details_present"
  end
end
