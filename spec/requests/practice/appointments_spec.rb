require "rails_helper"

RSpec.describe "Practice appointments", type: :request do
  let(:practice) do
    Practice.create!(
      name: "Test Medical Centre",
      timezone: "Europe/London",
      currency: "GBP",
      country_code: "GB"
    )
  end

  let(:user) do
    User.create!(
      email: "staff@example.com",
      password: "password123"
    )
  end

  let!(:staff_member) do
    StaffMember.create!(
      practice: practice,
      user: user,
      staff_type: "administrator",
      default_appointment_duration: 30
    )
  end

  describe "GET /practice/appointments" do
    context "when the user is a staff member" do
      before do
        sign_in user
      end

      it "returns http success" do
        get practice_appointments_path

        expect(response).to have_http_status(:success)
      end
    end

    context "when the user is not signed in" do
      it "redirects to sign in" do
        get practice_appointments_path

        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when the signed-in user is not a staff member" do
      let(:non_staff_user) do
        User.create!(
          email: "patient@example.com",
          password: "password123"
        )
      end

      before do
        sign_in non_staff_user
      end

      it "forbids access" do
        get practice_appointments_path

        expect(response).to have_http_status(:forbidden)
      end
    end
    context "when appointments belong to different practices" do
      let(:other_practice) do
        Practice.create!(
          name: "Other Medical Centre",
          timezone: "America/New_York",
          currency: "USD",
          country_code: "US"
        )
      end

      let(:other_user) do
        User.create!(
          email: "other-doctor@example.com",
          password: "password123"
        )
      end

      let(:other_clinician) do
        StaffMember.create!(
          practice: other_practice,
          user: other_user,
          staff_type: "doctor",
          default_appointment_duration: 30
        )
      end

      let(:other_patient) do
        Patient.create!(
          practice: other_practice,
          patient_number: "OTHER-001",
          first_name: "Hidden",
          last_name: "Patient",
          date_of_birth: Date.new(1990, 1, 1)
        )
      end

      before do
        sign_in user

        other_availability = AvailabilityBlock.create!(
          practice: other_practice,
          clinician: other_clinician,
          starts_at: 1.day.from_now.change(hour: 9),
          ends_at: 1.day.from_now.change(hour: 12)
        )

        other_slot = AppointmentSlot.create!(
          practice: other_practice,
          clinician: other_clinician,
          availability_block: other_availability,
          starts_at: 1.day.from_now.change(hour: 10),
          ends_at: 1.day.from_now.change(hour: 10, min: 30)
        )

        Appointment.create!(
          practice: other_practice,
          appointment_slot: other_slot,
          patient: other_patient,
          clinician: other_clinician,
          status: "booked",
          booked_at: Time.current
        )
      end

      it "does not expose appointments from another practice" do
        get practice_appointments_path

        expect(response).to have_http_status(:success)
        expect(response.body).not_to include("Hidden Patient")
      end
    end
  end

  describe "GET /practice/appointments/new" do
    before do
      sign_in user
    end

    it "returns http success" do
      get new_practice_appointment_path

      expect(response).to have_http_status(:success)
    end
  end
end
