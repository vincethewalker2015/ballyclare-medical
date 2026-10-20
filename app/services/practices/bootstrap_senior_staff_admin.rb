module Practices
  class BootstrapSeniorStaffAdmin
    class AlreadyProvisioned < StandardError; end

    def initialize(practice:, user:)
      @practice = practice
      @user = user
    end

    def call
      @practice.with_lock do
        raise AlreadyProvisioned, "Practice already has staff members" if @practice.staff_members.exists?

        @practice.staff_members.create!(
          first_name: "Practice",
          last_name: "Administrator",
          user: @user,
          staff_type: "administrator",
          access_level: "senior_staff_admin",
        )
      end
    end
  end
end
