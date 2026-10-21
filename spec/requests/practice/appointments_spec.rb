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
      access_level: "staff_admin",
      first_name: "Alex",
      last_name: "Morgan"
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

      it "shows a single booking link in the page header, outside the diary Turbo frame" do
        get practice_appointments_path

        page = response.parsed_body
        diary = page.at_css("turbo-frame#appointment_diary_list")
        expect(diary).to be_present

        booking_links = page.css("a[href='#{new_practice_appointment_path}']")
        expect(booking_links.size).to eq(1)
        expect(booking_links.first.ancestors("header")).to be_present
        expect(diary.css("a[href='#{new_practice_appointment_path}']")).to be_empty
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
          first_name: "John",
          last_name: "Doe"
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

      it "does not expose another practice's completed unpaid consultations in payment due" do
        foreign_appointment = other_practice.appointments.first
        foreign_appointment.update!(
          status: "completed",
          reason: "Other practice outstanding consultation"
        )

        create(
          :appointment_charge,
          appointment: foreign_appointment,
          patient: other_patient,
          practice: other_practice,
          amount_cents: 5000,
          status: "active"
        )

        get practice_appointments_path(view: "payment_due")

        expect(response).to have_http_status(:success)
        diary = response.parsed_body.at_css("turbo-frame#appointment_diary_list")
        expect(diary.text).not_to include("Other practice outstanding consultation")
        expect(diary.text).not_to include("Hidden Patient")
        expect(diary.text).to include("No outstanding payments")
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
          first_name: "Alex",
          last_name: "Morgan"
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

      it "shows the payment due empty state when no completed balances are outstanding" do
        appointment = nil

        Time.use_zone(practice.timezone) do
          appointment = create_diary_appointment(
            starts_at: Time.zone.now.beginning_of_day - 1.day + 10.hours,
            reason: "Fully paid completed consultation"
          )
        end

        appointment.update!(status: "completed")

        create(
          :appointment_charge,
          appointment: appointment,
          patient: appointment.patient,
          practice: practice,
          amount_cents: 5000,
          status: "active"
        )

        create(
          :payment,
          appointment: appointment,
          appointment_hold: nil,
          patient: appointment.patient,
          amount_cents: 5000,
          currency: "GBP",
          status: "succeeded"
        )

        get practice_appointments_path(view: "payment_due")

        expect(response).to have_http_status(:success)
        diary = response.parsed_body.at_css("turbo-frame#appointment_diary_list")
        expect(diary).to be_present
        expect(diary.text).to include("No outstanding payments")
        expect(diary.text).not_to include("No appointments today")
        expect(diary.text).not_to include("Fully paid completed consultation")
      end

      it "aligns appointments on the visual diary using practice-local time" do
        Time.use_zone(practice.timezone) do
          today = Time.zone.now.beginning_of_day

          create_diary_appointment(
            starts_at: today + 9.hours,
            reason: "Morning timeline appointment"
          )
          create_diary_appointment(
            starts_at: today + 11.hours,
            reason: "Later timeline appointment"
          )
        end

        get practice_appointments_path(view: "today", layout: "board")

        expect(response).to have_http_status(:success)
        diary = response.parsed_body.at_css("turbo-frame#appointment_diary_list")
        cards = diary.css("a[data-diary-appointment]")
        expect(cards.size).to eq(2)
        expect(cards.map { |card| card["data-start"] }).to eq(%w[09:00 11:00])
        expect(cards.map { |card| card["style"] }).to all(include("height: 45.0px"))
        expect(cards.first["style"]).to include("top: 90.0px")
        expect(cards.last["style"]).to include("top: 270.0px")
        expect(diary.text).to include("Morning timeline appointment", "Later timeline appointment")
      end

      it "uses compact clinician columns with a visible time axis" do
        clinician

        get practice_appointments_path(view: "today", layout: "board")

        expect(response).to have_http_status(:success)
        diary = response.parsed_body.at_css("turbo-frame#appointment_diary_list")
        expect(diary.at_css('[aria-label="Time of day"]')).to be_present
        expect(diary.at_css(".sticky.left-0.w-16")).to be_present
        expect(diary.at_css('section[aria-label="Alex Morgan appointments"].w-48')).to be_present
        expect(diary.at_css('h3[title="Alex Morgan"].truncate')).to be_present
      end

      it "retains the list layout when selected" do
        get practice_appointments_path(view: "today", layout: "list")

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.at_css("turbo-frame#appointment_diary_list")).to be_present
        expect(response.body).to include("No appointments on this date")
      end

      it "shows tomorrow's appointments on the visual diary" do
        Time.use_zone(practice.timezone) do
          tomorrow = Time.zone.today + 1.day
          create_diary_appointment(
            starts_at: Time.zone.local(tomorrow.year, tomorrow.month, tomorrow.day, 14),
            reason: "Tomorrow diary consultation"
          )
        end

        get practice_appointments_path(view: "tomorrow")

        expect(response).to have_http_status(:success)
        diary = response.parsed_body.at_css("turbo-frame#appointment_diary_list")
        expect(diary.text).to include("Tomorrow diary consultation")
        expect(diary.at_css('a[data-diary-appointment][data-start="14:00"]')).to be_present
      end

      it "shows a selected future date without including other dates" do
        selected_date = nil
        Time.use_zone(practice.timezone) do
          selected_date = Time.zone.today + 3.days
          create_diary_appointment(
            starts_at: Time.zone.local(selected_date.year, selected_date.month, selected_date.day, 11),
            reason: "Selected date consultation"
          )
          next_date = selected_date + 1.day
          create_diary_appointment(
            starts_at: Time.zone.local(next_date.year, next_date.month, next_date.day, 11),
            reason: "Different date consultation"
          )
        end

        get practice_appointments_path(view: "date", date: selected_date.iso8601)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Selected date consultation")
        expect(response.body).not_to include("Different date consultation")
        expect(response.parsed_body.at_css('input[type="date"]')["value"]).to eq(selected_date.iso8601)
      end

      it "preserves the selected date when switching to list layout" do
        selected_date = Time.use_zone(practice.timezone) { Time.zone.today + 2.days }

        get practice_appointments_path(view: "date", date: selected_date.iso8601, layout: "list")

        expect(response).to have_http_status(:success)
        expect(response.body).to include("No appointments on this date")
        expect(response.body).to include(selected_date.strftime("%A, %d %B %Y"))
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

      it "lists completed appointments with money due regardless of appointment date" do
        appointments = {}

        Time.use_zone(practice.timezone) do
          today = Time.zone.now.beginning_of_day

          appointments[:unpaid] = create_diary_appointment(
            starts_at: today - 3.days + 10.hours,
            reason: "Outstanding completed consultation"
          )
          appointments[:paid] = create_diary_appointment(
            starts_at: today - 2.days + 11.hours,
            reason: "Paid completed consultation"
          )
          appointments[:booked] = create_diary_appointment(
            starts_at: today + 1.day + 12.hours,
            reason: "Unpaid future booking"
          )
        end

        appointments.values_at(:unpaid, :paid).each do |appointment|
          appointment.update!(status: "completed")
        end

        appointments.each_value do |appointment|
          create(
            :appointment_charge,
            appointment: appointment,
            patient: appointment.patient,
            practice: practice,
            amount_cents: 5000,
            status: "active"
          )
        end

        create(
          :payment,
          appointment: appointments[:paid],
          appointment_hold: nil,
          patient: appointments[:paid].patient,
          amount_cents: 5000,
          currency: "GBP",
          status: "succeeded"
        )

        get practice_appointments_path(view: "payment_due")

        expect(response).to have_http_status(:success)

        diary = response.parsed_body.at_css("turbo-frame#appointment_diary_list")
        expect(diary.text).to include("Outstanding completed consultation")
        expect(diary.text).not_to include("Paid completed consultation")
        expect(diary.text).not_to include("Unpaid future booking")
      end

      it "filters payment due appointments by clinician" do
        other_clinician = StaffMember.create!(
          practice: practice,
          user: User.create!(
            email: "payment-due-doctor@example.com",
            password: "password123"
          ),
          staff_type: "doctor",
          first_name: "Other",
          last_name: "Clinician"
        )

        Time.use_zone(practice.timezone) do
          today = Time.zone.now.beginning_of_day

          [
            [ "Selected clinician payment due", clinician, 10 ],
            [ "Other clinician payment due", other_clinician, 11 ]
          ].each do |reason, appointment_clinician, hour|
            appointment = create_diary_appointment(
              starts_at: today - 2.days + hour.hours,
              reason: reason,
              clinician: appointment_clinician
            )
            appointment.update!(status: "completed")

            create(
              :appointment_charge,
              appointment: appointment,
              patient: appointment.patient,
              practice: practice,
              amount_cents: 5000,
              status: "active"
            )
          end
        end

        get practice_appointments_path(
          view: "payment_due",
          clinician_id: clinician.id
        )

        expect(response).to have_http_status(:success)
        diary = response.parsed_body.at_css("turbo-frame#appointment_diary_list")
        expect(diary.text).to include("Selected clinician payment due")
        expect(diary.text).not_to include("Other clinician payment due")
      end

      it "shows the remaining amount due for a part-paid completed consultation" do
        appointment = nil

        Time.use_zone(practice.timezone) do
          appointment = create_diary_appointment(
            starts_at: Time.zone.now.beginning_of_day - 2.days + 10.hours,
            reason: "Part-paid completed consultation"
          )
        end

        appointment.update!(status: "completed")

        create(
          :appointment_charge,
          appointment: appointment,
          patient: appointment.patient,
          practice: practice,
          amount_cents: 5000,
          status: "active"
        )

        create(
          :payment,
          appointment: appointment,
          appointment_hold: nil,
          patient: appointment.patient,
          amount_cents: 2000,
          currency: "GBP",
          status: "succeeded"
        )

        get practice_appointments_path(view: "payment_due")

        expect(response).to have_http_status(:success)
        diary = response.parsed_body.at_css("turbo-frame#appointment_diary_list")
        expect(diary.text).to include("Part-paid completed consultation")
        expect(diary.text).to include("GBP 30.00 due")
        expect(diary.text).to include("Part paid")
      end

      it "removes a completed consultation from payment due once fully paid" do
        appointment = nil

        Time.use_zone(practice.timezone) do
          appointment = create_diary_appointment(
            starts_at: Time.zone.now.beginning_of_day - 2.days + 10.hours,
            reason: "Consultation awaiting final payment"
          )
        end

        appointment.update!(status: "completed")

        create(
          :appointment_charge,
          appointment: appointment,
          patient: appointment.patient,
          practice: practice,
          amount_cents: 5000,
          status: "active"
        )

        create(
          :payment,
          appointment: appointment,
          appointment_hold: nil,
          patient: appointment.patient,
          amount_cents: 2000,
          currency: "GBP",
          status: "succeeded"
        )

        get practice_appointments_path(view: "payment_due")
        expect(response).to have_http_status(:success)
        diary = response.parsed_body.at_css("turbo-frame#appointment_diary_list")
        expect(diary.text).to include("Consultation awaiting final payment")

        create(
          :payment,
          appointment: appointment,
          appointment_hold: nil,
          patient: appointment.patient,
          amount_cents: 3000,
          currency: "GBP",
          status: "succeeded"
        )

        get practice_appointments_path(view: "payment_due")
        expect(response).to have_http_status(:success)
        diary = response.parsed_body.at_css("turbo-frame#appointment_diary_list")
        expect(diary.text).not_to include("Consultation awaiting final payment")
        expect(diary.text).to include("No outstanding payments")
        expect(appointment.reload.status).to eq("completed")
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
          first_name: "John",
          last_name: "Doe"
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
        first_name: "Alex",
        last_name: "Morgan"
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

  describe "GET /practice/appointments/:id" do
    before do
      sign_in user
    end

    it "warns staff when a completed appointment has an outstanding payment" do
      appointment = create(:appointment, practice: practice, status: "completed")

      create(
        :appointment_charge,
        appointment: appointment,
        patient: appointment.patient,
        practice: practice,
        amount_cents: 5000,
        status: "active"
      )

      get practice_appointment_path(appointment)

      expect(response).to have_http_status(:success)

      warning = response.parsed_body.at_css('[role="alert"]')
      expect(warning).to be_present
      expect(warning.text).to include("Payment outstanding")
      expect(warning.text).to include("GBP 50.00")
    end

    it "does not warn when a completed appointment is fully paid" do
      appointment = create(:appointment, practice: practice, status: "completed")

      create(
        :appointment_charge,
        appointment: appointment,
        patient: appointment.patient,
        practice: practice,
        amount_cents: 5000,
        status: "active"
      )

      create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        amount_cents: 5000,
        currency: "GBP",
        status: "succeeded",
        paid_at: Time.current
      )

      get practice_appointment_path(appointment)

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("Payment outstanding")
      expect(response.body).to include("GBP")
    end

    it "subscribes the appointment page to live refund updates" do
      appointment = create(:appointment, practice: practice)

      get practice_appointment_path(appointment)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.at_css("turbo-cable-stream-source")).to be_present
    end

    it "alerts staff when an appointment has a failed refund" do
      appointment = create(
        :appointment,
        practice: practice,
        status: "cancelled"
      )

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        amount_cents: 5000,
        currency: "GBP",
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_failed_refund",
        paid_at: Time.current
      )

      create(
        :refund,
        payment: payment,
        amount_cents: 5000,
        currency: "GBP",
        status: "failed",
        provider_refund_id: "re_failed_refund"
      )

      get practice_appointment_path(appointment)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Refund failed")
      expect(response.body).to include("Staff attention required")
    end

    it "does not show a failed refund warning for another appointment" do
      appointment = create(
        :appointment,
        practice: practice,
        status: "booked"
      )

      other_appointment = create(
        :appointment,
        practice: practice,
        status: "cancelled"
      )

      payment = create(
        :payment,
        appointment: other_appointment,
        appointment_hold: nil,
        patient: other_appointment.patient,
        amount_cents: 5000,
        currency: "GBP",
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_other_appointment",
        paid_at: Time.current
      )

      create(
        :refund,
        payment: payment,
        amount_cents: 5000,
        currency: "GBP",
        status: "failed",
        provider_refund_id: "re_other_appointment"
      )

      get practice_appointment_path(appointment)

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("Refund failed")
      expect(response.body).not_to include("Staff attention required")
    end

    it "shows the amount of a failed refund" do
      appointment = create(
        :appointment,
        practice: practice,
        status: "cancelled"
      )

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        amount_cents: 5000,
        currency: "GBP",
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_failed_refund_amount",
        paid_at: Time.current
      )

      create(
        :refund,
        payment: payment,
        amount_cents: 3750,
        currency: "GBP",
        status: "failed",
        provider_refund_id: "re_failed_refund_amount"
      )

      get practice_appointment_path(appointment)

      expect(response).to have_http_status(:success)

      alert = Nokogiri::HTML(response.body)
        .at_css('[role="alert"]')

      expect(alert).not_to be_nil
      expect(alert.text).to include("GBP 37.50")
    end

    it "shows when an appointment refund is processing" do
      appointment = create(
        :appointment,
        practice: practice,
        status: "cancelled"
      )

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        amount_cents: 5000,
        currency: "GBP",
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_processing_refund",
        paid_at: Time.current
      )

      create(
        :refund,
        payment: payment,
        amount_cents: 5000,
        currency: "GBP",
        status: "processing",
        provider_refund_id: "re_processing_refund"
      )

      get practice_appointment_path(appointment)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Refund processing")
      expect(response.body).to include("GBP 50.00")
      expect(response.body).not_to include("Staff attention required")
    end

    it "shows when an appointment refund has succeeded" do
      appointment = create(
        :appointment,
        practice: practice,
        status: "cancelled"
      )

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        amount_cents: 5000,
        currency: "GBP",
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_succeeded_refund",
        paid_at: Time.current
      )

      create(
        :refund,
        payment: payment,
        amount_cents: 3750,
        currency: "GBP",
        status: "succeeded",
        provider_refund_id: "re_succeeded_refund",
        refunded_at: Time.current
      )

      get practice_appointment_path(appointment)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Refund completed")
      expect(response.body).to include("GBP 37.50")
      expect(response.body).not_to include("Staff attention required")
      expect(response.body).not_to include("Refund processing")
    end

    it "shows when an appointment refund is pending" do
      appointment = create(
        :appointment,
        practice: practice,
        status: "cancelled"
      )

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        amount_cents: 5000,
        currency: "GBP",
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_pending_refund",
        paid_at: Time.current
      )

      create(
        :refund,
        payment: payment,
        amount_cents: 3750,
        currency: "GBP",
        status: "pending"
      )

      get practice_appointment_path(appointment)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Refund pending")
      expect(response.body).to include("GBP 37.50")
      expect(response.body).not_to include("Staff attention required")
      expect(response.body).not_to include("Refund failed")
    end

    it "shows failed and processing refunds on the same appointment" do
      appointment = create(
        :appointment,
        practice: practice,
        status: "cancelled"
      )

      payment = create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        amount_cents: 5000,
        currency: "GBP",
        status: "succeeded",
        provider: "stripe",
        provider_payment_id: "pi_multiple_refunds",
        paid_at: Time.current
      )

      create(
        :refund,
        payment: payment,
        amount_cents: 5000,
        currency: "GBP",
        status: "failed",
        provider_refund_id: "re_failed_attempt"
      )

      create(
        :refund,
        payment: payment,
        amount_cents: 5000,
        currency: "GBP",
        status: "processing",
        provider_refund_id: "re_processing_attempt"
      )

      get practice_appointment_path(appointment)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Refund failed")
      expect(response.body).to include("Staff attention required")
      expect(response.body).to include("Refund processing")
    end
  end

  describe "PATCH /practice/appointments/:id/status" do
    let(:appointment) do
      create(
        :appointment,
        practice: practice,
        status: "booked"
      )
    end

    let!(:charge) do
      create(
        :appointment_charge,
        appointment: appointment,
        patient: appointment.patient,
        practice: practice,
        amount_cents: 4000,
        status: "active"
      )
    end

    before do
      sign_in user

      create(
        :payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        amount_cents: 4000,
        currency: practice.currency,
        status: "pending"
      )
    end

    it "rejects cancellation while a payment is in progress" do
      expect {
        patch status_practice_appointment_path(appointment),
              params: { status: "cancelled" }
      }.not_to change(AppointmentStatusChange, :count)

      expect(response).to redirect_to(
        practice_appointment_path(appointment)
      )

      expect(flash[:alert]).to eq(
        "Cannot cancel an appointment while a payment is in progress."
      )

      expect(appointment.reload.status).to eq("booked")
      expect(charge.reload.status).to eq("active")
    end
  end
end
