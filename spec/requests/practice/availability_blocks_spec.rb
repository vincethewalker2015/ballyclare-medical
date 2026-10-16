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

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when active availability already overlaps" do
  before do
    AvailabilityBlock.create!(
      practice: practice,
      clinician: clinician,
      starts_at: Time.find_zone!(practice.timezone).parse("2026-10-20 10:00"),
      ends_at: Time.find_zone!(practice.timezone).parse("2026-10-20 11:00"),
      slot_duration_minutes: 30,
      bookable_online: true
    )
  end

  it "rejects the overlap without creating another block" do
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
    }.not_to change(AvailabilityBlock, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("overlap")
  end
end

    context "when replacing cancelled availability" do
      before do
        cancelled_block = AvailabilityBlock.create!(
          practice: practice,
          clinician: clinician,
          starts_at: Time.find_zone!(practice.timezone).parse("2026-10-20 09:00"),
          ends_at: Time.find_zone!(practice.timezone).parse("2026-10-20 12:00"),
          slot_duration_minutes: 30,
          bookable_online: true,
          cancelled_at: 1.day.ago
        )

        Availability::GenerateSlots.new(cancelled_block).call
      end

      it "creates new slots while preserving the cancelled block's slots" do
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
          .and change(AppointmentSlot, :count).by(6)

        expect(response).to redirect_to(practice_availability_blocks_path)

        cancelled_block = AvailabilityBlock.cancelled.find_by!(clinician: clinician)
        expect(cancelled_block.appointment_slots.count).to eq(6)

        replacement = AvailabilityBlock.active.find_by!(
          clinician: clinician,
          practice: practice
        )
        expect(replacement.appointment_slots.count).to eq(6)
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
  describe "GET /practice/availability/:id/edit" do
  let!(:availability_block) do
    AvailabilityBlock.create!(
      practice: practice,
      clinician: clinician,
      starts_at: Time.zone.parse("2026-10-20 09:00"),
      ends_at: Time.zone.parse("2026-10-20 12:00"),
      slot_duration_minutes: 30,
      bookable_online: true
    )
  end

  it "returns http success" do
    get edit_practice_availability_block_path(availability_block)

    expect(response).to have_http_status(:success)
  end

  context "when the availability belongs to another practice" do
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
        email: "other-edit-doctor@example.com",
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

    let(:other_availability_block) do
      AvailabilityBlock.create!(
        practice: other_practice,
        clinician: other_clinician,
        starts_at: Time.zone.parse("2026-10-20 09:00"),
        ends_at: Time.zone.parse("2026-10-20 12:00"),
        slot_duration_minutes: 30,
        bookable_online: true
      )
    end

    it "returns not found" do
      get edit_practice_availability_block_path(
        other_availability_block
      )

      expect(response).to have_http_status(:not_found)
    end
  end
end

  describe "PATCH /practice/availability/:id" do
    let!(:availability_block) do
      AvailabilityBlock.create!(
        practice: practice,
        clinician: clinician,
        starts_at: Time.zone.parse("2026-10-20 09:00"),
        ends_at: Time.zone.parse("2026-10-20 12:00"),
        slot_duration_minutes: 30,
        bookable_online: true
      )
    end

    before do
      Availability::GenerateSlots.new(
        availability_block
      ).call
    end

    def update_availability(params = {})
      patch practice_availability_block_path(availability_block),
            params: {
              availability_block: {
                clinician_id: clinician.id,
                date: "2026-10-20",
                starts_at: "10:00",
                ends_at: "13:00",
                slot_duration_minutes: 30,
                bookable_online: "1"
              }.merge(params)
            }
    end

    it "updates the availability block" do
      update_availability

      availability_block.reload

      expect(
        availability_block.starts_at
          .in_time_zone(practice.timezone)
          .strftime("%H:%M")
      ).to eq("10:00")

      expect(
        availability_block.ends_at
          .in_time_zone(practice.timezone)
          .strftime("%H:%M")
      ).to eq("13:00")
    end

    it "regenerates the appointment slots" do
      original_slot_ids =
        availability_block.appointment_slots.pluck(:id)

      update_availability

      slots = availability_block
        .appointment_slots
        .reload
        .order(:starts_at)

      expect(slots.count).to eq(6)

      expect(
        slots.pluck(:id) & original_slot_ids
      ).to be_empty

      expect(
        slots.first.starts_at
          .in_time_zone(practice.timezone)
          .strftime("%H:%M")
      ).to eq("10:00")

      expect(
        slots.last.ends_at
          .in_time_zone(practice.timezone)
          .strftime("%H:%M")
      ).to eq("13:00")
    end

    it "redirects to the availability index" do
      update_availability

      expect(response).to redirect_to(
        practice_availability_blocks_path
      )
    end

    context "when the end time is before the start time" do
      it "does not update the availability" do
        original_starts_at = availability_block.starts_at
        original_ends_at = availability_block.ends_at

        update_availability(
          starts_at: "12:00",
          ends_at: "09:00"
        )

        availability_block.reload

        expect(availability_block.starts_at)
          .to eq(original_starts_at)

        expect(availability_block.ends_at)
          .to eq(original_ends_at)

        expect(response)
          .to have_http_status(:unprocessable_content)
      end
    end

    context "when a slot has historical appointment hold data" do
      let!(:patient) do
        Patient.create!(
          practice: practice,
          patient_number: "AVAIL-001",
          first_name: "Test",
          last_name: "Patient",
          date_of_birth: Date.new(1990, 1, 1)
        )
      end

      let!(:appointment_hold) do
        AppointmentHold.create!(
          appointment_slot:
            availability_block
              .appointment_slots
              .order(:starts_at)
              .first,
          patient: patient,
          expires_at: 1.hour.ago
        )
      end

      it "does not reschedule the availability" do
        original_starts_at = availability_block.starts_at
        original_ends_at = availability_block.ends_at
        original_slot_ids =
          availability_block.appointment_slots.pluck(:id)

        update_availability

        availability_block.reload

        expect(availability_block.starts_at)
          .to eq(original_starts_at)

        expect(availability_block.ends_at)
          .to eq(original_ends_at)

        expect(
          availability_block.appointment_slots.pluck(:id)
        ).to match_array(original_slot_ids)

        expect(AppointmentHold.exists?(appointment_hold.id))
          .to be(true)
      end

      it "redirects with an alert" do
        update_availability

        expect(response).to redirect_to(
          practice_availability_blocks_path
        )

        expect(flash[:alert]).to eq(
          "Availability with appointment hold history cannot be rescheduled."
        )
      end
    end

    context "when the availability belongs to another practice" do
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
          email: "other-update-doctor@example.com",
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

      let(:other_availability_block) do
        AvailabilityBlock.create!(
          practice: other_practice,
          clinician: other_clinician,
          starts_at: Time.zone.parse("2026-10-20 09:00"),
          ends_at: Time.zone.parse("2026-10-20 12:00"),
          slot_duration_minutes: 30,
          bookable_online: true
        )
      end

      it "returns not found" do
        patch practice_availability_block_path(
          other_availability_block
        ),
        params: {
          availability_block: {
            clinician_id: other_clinician.id,
            date: "2026-10-20",
            starts_at: "10:00",
            ends_at: "13:00",
            slot_duration_minutes: 30,
            bookable_online: "1"
          }
        }

        expect(response).to have_http_status(:not_found)
      end
    end

    describe "PATCH /practice/availability/:id/cancel" do
      before do
        sign_in user
      end

      it "cancels the availability block" do
        patch cancel_practice_availability_block_path(
          availability_block
        )

        expect(response).to redirect_to(
          practice_availability_blocks_path
        )

        expect(
          availability_block.reload
        ).to be_cancelled
      end

      it "does not allow availability from another practice to be cancelled" do
        other_practice = Practice.create!(
          name: "Other Medical Centre",
          timezone: "America/New_York",
          currency: "USD",
          country_code: "US"
        )

        other_user = User.create!(
          email: "other-doctor@example.com",
          password: "password123"
        )

        other_clinician = StaffMember.create!(
          practice: other_practice,
          user: other_user,
          staff_type: "doctor",
          default_appointment_duration: 30
        )

        other_block = AvailabilityBlock.create!(
          practice: other_practice,
          clinician: other_clinician,
          starts_at: 1.day.from_now.change(hour: 9),
          ends_at: 1.day.from_now.change(hour: 10),
          slot_duration_minutes: 30,
          bookable_online: true
        )

        patch cancel_practice_availability_block_path(
          other_block
        )

        expect(response).to have_http_status(:not_found)
        expect(other_block.reload).to be_active
      end
    end
  end
end
