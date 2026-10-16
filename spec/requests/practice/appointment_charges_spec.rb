require "rails_helper"

RSpec.describe "Practice appointment charges", type: :request do
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

  let(:clinician_user) do
    User.create!(
      email: "doctor@example.com",
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
      patient_number: "TEST-001",
      first_name: "Test",
      last_name: "Patient",
      date_of_birth: Date.new(1990, 1, 1)
    )
  end

  let(:availability_block) do
    AvailabilityBlock.create!(
      practice: practice,
      clinician: clinician,
      starts_at: 1.day.from_now.change(hour: 9),
      ends_at: 1.day.from_now.change(hour: 12)
    )
  end

  let(:appointment_slot) do
    AppointmentSlot.create!(
      practice: practice,
      clinician: clinician,
      availability_block: availability_block,
      starts_at: 1.day.from_now.change(hour: 10),
      ends_at: 1.day.from_now.change(hour: 10, min: 30)
    )
  end

  let(:appointment) do
    Appointment.create!(
      practice: practice,
      appointment_slot: appointment_slot,
      patient: patient,
      clinician: clinician,
      status: "booked",
      booked_at: Time.current
    )
  end

  before do
    sign_in user
  end

  describe "GET /practice/appointments/:appointment_id/charge/new" do
    it "returns http success" do
      get new_practice_appointment_charge_path(appointment)

      expect(response).to have_http_status(:success)
    end

    context "when the appointment is cancelled" do
      before do
        appointment.update!(status: "cancelled")
      end

      it "redirects back to the appointment with an error" do
        get new_practice_appointment_charge_path(appointment)

        expect(response).to redirect_to(
          practice_appointment_path(appointment)
        )

        expect(flash[:alert]).to eq(
          "Cannot add charges to a cancelled appointment."
        )
      end
    end
  end

  describe "POST /practice/appointments/:appointment_id/charge" do
    context "when the appointment is cancelled" do
      before do
        appointment.update!(status: "cancelled")
      end

      it "rejects the charge and redirects with an error" do
        expect {
          post practice_appointment_charge_path(appointment),
              params: {
                description: "Remove stitches",
                amount: "35.00"
              }
        }.not_to change(AppointmentCharge, :count)

        expect(response).to redirect_to(
          practice_appointment_path(appointment)
        )

        expect(flash[:alert]).to eq(
          "Cannot add charges to a cancelled appointment."
        )
      end
    end

    context "with valid details" do
      it "creates an additional charge" do
        expect {
          post practice_appointment_charge_path(appointment),
               params: {
                 description: "Remove stitches",
                 amount: "35.00"
               }
        }.to change(AppointmentCharge, :count).by(1)

        charge = AppointmentCharge.order(:created_at).last

        expect(charge).to have_attributes(
          appointment: appointment,
          patient: patient,
          practice: practice,
          created_by: user,
          description: "Remove stitches",
          charge_type: "additional",
          amount_cents: 3500,
          currency: "GBP",
          status: "active"
        )
      end

      it "redirects back to the appointment" do
        post practice_appointment_charge_path(appointment),
             params: {
               description: "Remove stitches",
               amount: "35.00"
             }

        expect(response).to redirect_to(
          practice_appointment_path(appointment)
        )
      end
    end

    context "when the appointment belongs to another practice" do
      let(:other_practice) do
        Practice.create!(
          name: "Other Medical Centre",
          timezone: "America/New_York",
          currency: "USD",
          country_code: "US"
        )
      end

      let(:other_clinician_user) do
        User.create!(
          email: "other-doctor@example.com",
          password: "password123"
        )
      end

      let(:other_clinician) do
        StaffMember.create!(
          practice: other_practice,
          user: other_clinician_user,
          staff_type: "doctor",
          default_appointment_duration: 30
        )
      end

      let(:other_patient) do
        Patient.create!(
          practice: other_practice,
          patient_number: "OTHER-001",
          first_name: "Other",
          last_name: "Patient",
          date_of_birth: Date.new(1990, 1, 1)
        )
      end

      let(:other_availability_block) do
        AvailabilityBlock.create!(
          practice: other_practice,
          clinician: other_clinician,
          starts_at: 2.days.from_now.change(hour: 9),
          ends_at: 2.days.from_now.change(hour: 12)
        )
      end

      let(:other_slot) do
        AppointmentSlot.create!(
          practice: other_practice,
          clinician: other_clinician,
          availability_block: other_availability_block,
          starts_at: 2.days.from_now.change(hour: 10),
          ends_at: 2.days.from_now.change(hour: 10, min: 30)
        )
      end

      let(:other_appointment) do
        Appointment.create!(
          practice: other_practice,
          appointment_slot: other_slot,
          patient: other_patient,
          clinician: other_clinician,
          status: "booked",
          booked_at: Time.current
        )
      end

      it "does not allow a charge to be added" do
        expect {
          post practice_appointment_charge_path(other_appointment),
              params: {
                description: "Unauthorised charge",
                amount: "35.00"
              }
        }.not_to change(AppointmentCharge, :count)

        expect(response).to have_http_status(:not_found)
      end
    end

    context "with a blank description" do
      it "does not create a charge" do
        expect {
          post practice_appointment_charge_path(appointment),
               params: {
                 description: "",
                 amount: "35.00"
               }
        }.not_to change(AppointmentCharge, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "with an invalid amount" do
      it "does not create a charge" do
        expect {
          post practice_appointment_charge_path(appointment),
               params: {
                 description: "Remove stitches",
                 amount: "invalid"
               }
        }.not_to change(AppointmentCharge, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when browser-supplied billing attributes are submitted" do
      it "does not allow them to override server-controlled attributes" do
        post practice_appointment_charge_path(appointment),
             params: {
               description: "Remove stitches",
               amount: "35.00",
               currency: "USD",
               charge_type: "appointment",
               status: "voided"
             }

        charge = AppointmentCharge.order(:created_at).last

        expect(charge).to have_attributes(
          currency: "GBP",
          charge_type: "additional",
          status: "active"
        )
      end
    end
  end
end
