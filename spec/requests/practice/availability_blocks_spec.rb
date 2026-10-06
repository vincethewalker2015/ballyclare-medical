require "rails_helper"

RSpec.describe "Practice availability", type: :request do
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

  let!(:clinician) do
    StaffMember.create!(
      practice: practice,
      user: clinician_user,
      staff_type: "doctor",
      first_name: "Test",
      last_name: "Doctor",
      default_appointment_duration: 30
    )
  end

  before do
    sign_in user
  end

  describe "GET /practice/availability" do
    it "returns http success" do
      get practice_availability_blocks_path

      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /practice/availability/new" do
    it "returns http success" do
      get new_practice_availability_block_path

      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /practice/availability" do
    it "creates availability for the current practice" do
      expect {
        post practice_availability_blocks_path,
             params: {
               availability_block: {
                 clinician_id: clinician.id,
                 date: "2026-10-20",
                 starts_at: "09:00",
                 ends_at: "12:00",
                 slot_duration_minutes: 30,
                 bookable_online: "1"
               }
             }
      }.to change(AvailabilityBlock, :count).by(1)

      block = AvailabilityBlock.order(:created_at).last

      expect(block).to have_attributes(
        practice: practice,
        clinician: clinician,
        slot_duration_minutes: 30,
        bookable_online: true
      )
    end

    it "interprets entered times using the practice timezone" do
      post practice_availability_blocks_path,
           params: {
             availability_block: {
               clinician_id: clinician.id,
               date: "2026-10-20",
               starts_at: "09:00",
               ends_at: "12:00",
               slot_duration_minutes: 30,
               bookable_online: "1"
             }
           }

      block = AvailabilityBlock.order(:created_at).last

      expect(
        block.starts_at.in_time_zone(practice.timezone).strftime("%H:%M")
      ).to eq("09:00")

      expect(
        block.ends_at.in_time_zone(practice.timezone).strftime("%H:%M")
      ).to eq("12:00")
    end

    it "generates appointment slots" do
      post practice_availability_blocks_path,
           params: {
             availability_block: {
               clinician_id: clinician.id,
               date: "2026-10-20",
               starts_at: "09:00",
               ends_at: "12:00",
               slot_duration_minutes: 30,
               bookable_online: "1"
             }
           }

      block = AvailabilityBlock.order(:created_at).last

      expect(block.appointment_slots.count).to eq(6)
    end

    it "redirects to the availability index" do
      post practice_availability_blocks_path,
           params: {
             availability_block: {
               clinician_id: clinician.id,
               date: "2026-10-20",
               starts_at: "09:00",
               ends_at: "12:00",
               slot_duration_minutes: 30,
               bookable_online: "1"
             }
           }

      expect(response).to redirect_to(
        practice_availability_blocks_path
      )
    end

    context "when the end time is before the start time" do
      it "does not create availability" do
        expect {
          post practice_availability_blocks_path,
               params: {
                 availability_block: {
                   clinician_id: clinician.id,
                   date: "2026-10-20",
                   starts_at: "12:00",
                   ends_at: "09:00",
                   slot_duration_minutes: 30,
                   bookable_online: "1"
                 }
               }
        }.not_to change(AvailabilityBlock, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when the clinician belongs to another practice" do
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
          first_name: "Other",
          last_name: "Doctor",
          default_appointment_duration: 30
        )
      end

      it "does not allow availability to be created" do
        expect {
          post practice_availability_blocks_path,
               params: {
                 availability_block: {
                   clinician_id: other_clinician.id,
                   date: "2026-10-20",
                   starts_at: "09:00",
                   ends_at: "12:00",
                   slot_duration_minutes: 30,
                   bookable_online: "1"
                 }
               }
        }.not_to change(AvailabilityBlock, :count)

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
