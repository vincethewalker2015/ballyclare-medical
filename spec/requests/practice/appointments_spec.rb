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

        Time.use_zone(other_practice.timezone) do
          starts_at = Time.zone.now.beginning_of_day + 1.day + 10.hours

          other_availability = AvailabilityBlock.create!(
            practice: other_practice,
            clinician: other_clinician,
            starts_at: starts_at,
            ends_at: starts_at + 30.minutes,
            slot_duration_minutes: 30,
            bookable_online: true
          )

          other_slot = AppointmentSlot.create!(
            practice: other_practice,
            clinician: other_clinician,
            availability_block: other_availability,
            starts_at: starts_at,
            ends_at: starts_at + 30.minutes
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
      end

      it "does not expose appointments from another practice" do
        get practice_appointments_path(view: "upcoming")

        expect(response).to have_http_status(:success)
        expect(response.body).not_to include("Hidden Patient")
      end
    end

    context "when filtering the appointment diary" do
      let(:clinician_user) do
        User.create!(
          email: "diary-doctor@example.com",
          password: "password123"
        )
      end

      let(:clinician) do
        StaffMember.create!(
          practice: practice,
          user: clinician_user,
          staff_type: "doctor",
          default_appointment_duration: 30
        )
      end

      let(:patient) do
        Patient.create!(
          practice: practice,
          patient_number: "DIARY-001",
          first_name: "Diary",
          last_name: "Patient",
          date_of_birth: Date.new(1990, 1, 1)
        )
      end

      before do
        sign_in user
      end

      def create_diary_appointment(starts_at:, reason:, clinician: self.clinician)
        availability = AvailabilityBlock.create!(
          practice: practice,
          clinician: clinician,
          starts_at: starts_at,
          ends_at: starts_at + 30.minutes,
          slot_duration_minutes: 30,
          bookable_online: true
        )

        slot = AppointmentSlot.create!(
          practice: practice,
          clinician: clinician,
          availability_block: availability,
          starts_at: starts_at,
          ends_at: starts_at + 30.minutes
        )

        Appointment.create!(
          practice: practice,
          appointment_slot: slot,
          patient: patient,
          clinician: clinician,
          reason: reason,
          status: "booked",
          booked_at: Time.current
        )
      end

      it "shows today's appointments by default" do
        Time.use_zone(practice.timezone) do
          today = Time.zone.now.beginning_of_day

          create_diary_appointment(
            starts_at: today + 12.hours,
            reason: "Today appointment"
          )

          create_diary_appointment(
            starts_at: today + 2.days + 12.hours,
            reason: "Upcoming appointment"
          )

          create_diary_appointment(
            starts_at: today - 1.day + 12.hours,
            reason: "Past appointment"
          )
        end

        get practice_appointments_path

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Today appointment")
        expect(response.body).not_to include("Upcoming appointment")
        expect(response.body).not_to include("Past appointment")
      end

      it "shows future appointments in the upcoming view" do
        Time.use_zone(practice.timezone) do
          today = Time.zone.now.beginning_of_day

          create_diary_appointment(
            starts_at: today + 2.days + 12.hours,
            reason: "Upcoming appointment"
          )

          create_diary_appointment(
            starts_at: today + 12.hours,
            reason: "Today appointment"
          )
        end

        get practice_appointments_path(view: "upcoming")

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Upcoming appointment")
        expect(response.body).not_to include("Today appointment")
      end

      it "shows earlier appointments in the past view" do
        Time.use_zone(practice.timezone) do
          today = Time.zone.now.beginning_of_day

          create_diary_appointment(
            starts_at: today - 1.day + 12.hours,
            reason: "Past appointment"
          )

          create_diary_appointment(
            starts_at: today + 12.hours,
            reason: "Today appointment"
          )
        end

        get practice_appointments_path(view: "past")

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Past appointment")
        expect(response.body).not_to include("Today appointment")
      end

      it "shows the financial state of an appointment" do
        appointment = nil

        Time.use_zone(practice.timezone) do
          appointment = create_diary_appointment(
            starts_at: Time.zone.now.beginning_of_day + 12.hours,
            reason: "Financial status appointment"
          )
        end

        create(
          :appointment_charge,
          appointment: appointment,
          patient: appointment.patient,
          practice: appointment.practice,
          amount_cents: 5000,
          status: "active"
        )

        create(
          :payment,
          appointment: appointment,
          appointment_hold: nil,
          patient: appointment.patient,
          amount_cents: 2000,
          currency: appointment.practice.currency,
          status: "succeeded"
        )

        get practice_appointments_path

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Financial status appointment")
        expect(response.body).to include("Part paid")
      end

      it "filters appointments by the selected clinician" do
        other_clinician = StaffMember.create!(
          practice: practice,
          user: User.create!(
            email: "second-diary-doctor@example.com",
            password: "password123"
          ),
          staff_type: "doctor",
          default_appointment_duration: 30,
          first_name: "Second",
          last_name: "Doctor"
        )

        Time.use_zone(practice.timezone) do
          today = Time.zone.now.beginning_of_day

          create_diary_appointment(
            starts_at: today + 10.hours,
            reason: "Selected clinician appointment"
          )

          create_diary_appointment(
            starts_at: today + 11.hours,
            reason: "Other clinician appointment",
            clinician: other_clinician
          )
        end

        get practice_appointments_path(
          view: "today",
          clinician_id: clinician.id
        )

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Selected clinician appointment")
        expect(response.body).not_to include("Other clinician appointment")
      end

      it "rejects a clinician belonging to another practice" do
        other_practice = Practice.create!(
          name: "Another Medical Centre",
          timezone: "America/New_York",
          currency: "USD",
          country_code: "US"
        )

        other_clinician = StaffMember.create!(
          practice: other_practice,
          user: User.create!(
            email: "external-diary-doctor@example.com",
            password: "password123"
          ),
          staff_type: "doctor",
          default_appointment_duration: 30
        )

        get practice_appointments_path(
          view: "today",
          clinician_id: other_clinician.id
        )

        expect(response).to have_http_status(:not_found)
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

  describe "GET /practice/appointments/available_slots" do
    let(:clinician) do
      StaffMember.create!(
        practice: practice,
        user: User.create!(
          email: "doctor@example.com",
          password: "password123"
        ),
        staff_type: "doctor",
        default_appointment_duration: 30
      )
    end

    let(:active_availability) do
      AvailabilityBlock.create!(
        practice: practice,
        clinician: clinician,
        starts_at: 1.day.from_now.change(hour: 9),
        ends_at: 1.day.from_now.change(hour: 10),
        slot_duration_minutes: 30,
        bookable_online: true
      )
    end

    let(:cancelled_availability) do
      AvailabilityBlock.create!(
        practice: practice,
        clinician: clinician,
        starts_at: 2.days.from_now.change(hour: 9),
        ends_at: 2.days.from_now.change(hour: 10),
        slot_duration_minutes: 30,
        bookable_online: true,
        cancelled_at: Time.current
      )
    end

    let!(:active_slot) do
      AppointmentSlot.create!(
        practice: practice,
        clinician: clinician,
        availability_block: active_availability,
        starts_at: 1.day.from_now.change(hour: 9),
        ends_at: 1.day.from_now.change(hour: 9, min: 30)
      )
    end

    let!(:cancelled_slot) do
      AppointmentSlot.create!(
        practice: practice,
        clinician: clinician,
        availability_block: cancelled_availability,
        starts_at: 2.days.from_now.change(hour: 9),
        ends_at: 2.days.from_now.change(hour: 9, min: 30)
      )
    end

    before do
      sign_in user
    end

    it "returns slots from active availability only" do
      get available_slots_practice_appointments_path,
          params: { clinician_id: clinician.id },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(active_slot.id)
      expect(response.body).not_to include(cancelled_slot.id)
    end

    it "returns a future slot when its previous appointment was cancelled" do
      patient = create(:patient, practice: practice)

      original_appointment = create(
        :appointment,
        practice: practice,
        appointment_slot: active_slot,
        patient: patient,
        clinician: clinician,
        status: "cancelled"
      )

      get available_slots_practice_appointments_path,
          params: { clinician_id: clinician.id },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(active_slot.id)

      expect(original_appointment.reload.status).to eq("cancelled")
      expect(original_appointment).to be_persisted
    end

    it "does not return a future slot with an active appointment" do
      patient = create(:patient, practice: practice)

      create(
        :appointment,
        practice: practice,
        appointment_slot: active_slot,
        patient: patient,
        clinician: clinician,
        status: "booked"
      )

      get available_slots_practice_appointments_path,
          params: { clinician_id: clinician.id },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include(active_slot.id)
    end
  end
end
