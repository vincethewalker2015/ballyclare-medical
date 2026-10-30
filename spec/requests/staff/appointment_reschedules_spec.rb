require "rails_helper"

RSpec.describe "Staff appointment rescheduling", type: :request do
  let(:practice) { create(:practice) }
  let(:staff_user) { create(:user) }
  let(:staff_member) do
    create(:staff_member, practice: practice, user: staff_user,
      staff_type: "administrator", access_level: "staff_admin")
  end
  let(:clinician) { create(:staff_member, practice: practice) }
  let(:appointment) { create(:appointment, practice: practice, clinician: clinician) }
  let(:replacement) do
    create(:appointment_slot, practice: practice, clinician: clinician,
      availability_block: appointment.appointment_slot.availability_block,
      starts_at: appointment.appointment_slot.starts_at + 20.minutes,
      ends_at: appointment.appointment_slot.starts_at + 40.minutes)
  end

  before do
    staff_member
    appointment.appointment_slot.update!(starts_at: 3.days.from_now,
      ends_at: 3.days.from_now + 20.minutes)
  end

  it "requires authentication" do
    patch practice_appointment_reschedule_path(appointment), params: { appointment_slot_id: replacement.id }
    expect(response).to redirect_to(new_user_session_path)
  end

  it "shows eligible slots to practice administrators" do
    sign_in staff_user
    get edit_practice_appointment_reschedule_path(appointment)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Reschedule appointment")
  end

  it "reschedules with an audit trail" do
    sign_in staff_user
    expect {
      patch practice_appointment_reschedule_path(appointment), params: { appointment_slot_id: replacement.id }
    }.to change(AuditEvent, :count).by(1)
    expect(appointment.reload.appointment_slot).to eq(replacement)
    expect(AuditEvent.last.user).to eq(staff_user)
  end

  it "permits staff overrides within 24 hours" do
    appointment.appointment_slot.update!(starts_at: 12.hours.from_now,
      ends_at: 12.hours.from_now + 20.minutes)
    sign_in staff_user
    patch practice_appointment_reschedule_path(appointment), params: { appointment_slot_id: replacement.id }
    expect(appointment.reload.appointment_slot).to eq(replacement)
  end

  it "denies basic staff access" do
    staff_member.update!(access_level: "staff")
    sign_in staff_user
    patch practice_appointment_reschedule_path(appointment), params: { appointment_slot_id: replacement.id }
    expect(response).to have_http_status(:forbidden)
  end

  it "isolates practices" do
    foreign = create(:appointment)
    sign_in staff_user
    patch practice_appointment_reschedule_path(foreign), params: { appointment_slot_id: replacement.id }
    expect(response).to have_http_status(:not_found)
  end

  it "restricts clinicians to their own appointments" do
    staff_member.update!(staff_type: "doctor", access_level: "staff_clinician")
    sign_in staff_user
    patch practice_appointment_reschedule_path(appointment), params: { appointment_slot_id: replacement.id }
    expect(response).to have_http_status(:not_found)
  end

  it "rejects changing clinician type" do
    nurse = create(:staff_member, practice: practice, staff_type: "nurse")
    replacement.update!(clinician: nurse,
      availability_block: create(:availability_block, practice: practice, clinician: nurse))
    sign_in staff_user
    patch practice_appointment_reschedule_path(appointment), params: { appointment_slot_id: replacement.id }
    expect(response).to redirect_to(edit_practice_appointment_reschedule_path(appointment))
    expect(appointment.reload.appointment_slot).not_to eq(replacement)
  end
end
