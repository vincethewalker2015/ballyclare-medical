require "rails_helper"

RSpec.describe "Clinician consultation entry", type: :request do
  let(:group) { create(:medical_group) }
  let(:practice) { create(:practice, medical_group: group) }
  let(:sibling) { create(:practice, medical_group: group) }
  let(:user) { create(:user) }
  let!(:clinician) do
    create(:staff_member, practice: practice, user: user, staff_type: "doctor", access_level: "staff_clinician")
  end
  let!(:appointment) { create(:appointment, practice: practice, clinician: clinician) }

  before { sign_in user }

  it "shows the assigned clinician a read-only, Ballyclare-styled consultation and audits access" do
    expect {
      get practice_appointment_consultation_path(appointment)
    }.to change { AuditEvent.where(action: "clinical.consultation_viewed", auditable: appointment).count }.by(1)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Consultation", appointment.patient.patient_number, "text-medical-navy")
    expect(response.body).to include("No previous clinical encounters")
  end

  it "displays previous encounters and notes from the same practice" do
    previous = Encounter.create!(
      practice: practice, patient: appointment.patient, clinician: clinician,
      encounter_type: "consultation", started_at: 2.days.ago
    )
    note = ClinicalNote.create!(
      encounter: previous, patient: appointment.patient, author: clinician,
      note_type: "consultation", body: "Prior clinical observation"
    )

    get practice_appointment_consultation_path(appointment)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(note.body)
  end

  it "does not show sibling-practice clinical notes even for the same medical group" do
    sibling_patient = create(:patient, practice: sibling)
    sibling_clinician = create(:staff_member, practice: sibling, staff_type: "doctor", access_level: "staff_clinician")
    sibling_encounter = Encounter.create!(
      practice: sibling, patient: sibling_patient, clinician: sibling_clinician,
      encounter_type: "consultation", started_at: 2.days.ago
    )
    ClinicalNote.create!(
      encounter: sibling_encounter, patient: sibling_patient, author: sibling_clinician,
      note_type: "consultation", body: "Sibling practice private note"
    )

    get practice_appointment_consultation_path(appointment)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Sibling practice private note")
  end

  it "forbids a clinician's colleague from viewing the consultation without logging access" do
    other = create(:staff_member, practice: practice, staff_type: "doctor", access_level: "staff_clinician")
    other_appointment = create(:appointment, practice: practice, clinician: other)

    expect {
      get practice_appointment_consultation_path(other_appointment)
    }.not_to change(AuditEvent, :count)

    expect(response).to have_http_status(:forbidden)
  end

  it "returns not found for appointments in a sibling practice" do
    sibling_appointment = create(:appointment, practice: sibling)

    get practice_appointment_consultation_path(sibling_appointment)

    expect(response).to have_http_status(:not_found)
  end

  it "denies basic and administrative staff access, including senior administrators" do
    %w[staff staff_admin senior_staff_admin].each do |level|
      clinician.update!(access_level: level)
      get practice_appointment_consultation_path(appointment)
      expect(response).to have_http_status(:forbidden)
    end
  end

  it "denies deactivated clinician membership" do
    clinician.update!(active: false)

    get practice_appointment_consultation_path(appointment)

    expect(response).to have_http_status(:forbidden)
  end

  it "denies an inactive membership at a sibling practice after switching" do
    sibling_member = create(:staff_member, user: user, practice: sibling, staff_type: "doctor", access_level: "staff_clinician", active: false)
    sibling_appointment = create(:appointment, practice: sibling, clinician: sibling_member)
    patch practice_selection_path, params: { practice_id: sibling.id }

    expect(response).to have_http_status(:forbidden)
    get practice_appointment_consultation_path(sibling_appointment)
    expect(response).to have_http_status(:not_found)
  end

  it "uses the selected practice's local clinician identity rather than the home role" do
    sibling_member = create(:staff_member, user: user, practice: sibling, staff_type: "doctor", access_level: "staff_clinician")
    sibling_appointment = create(:appointment, practice: sibling, clinician: sibling_member)
    patch practice_selection_path, params: { practice_id: sibling.id }

    expect(response).to redirect_to(practice_appointments_path)
    get practice_appointment_consultation_path(sibling_appointment)
    expect(response).to have_http_status(:ok)
    get practice_appointment_consultation_path(appointment)
    expect(response).to have_http_status(:not_found)
  end
  describe "starting a consultation" do
    before { appointment.update!(status: "arrived") }

    it "creates one encounter and transitions the appointment with an audit event" do
      expect {
        post practice_appointment_consultation_path(appointment)
      }.to change(Encounter, :count).by(1)
        .and change { AuditEvent.where(action: "clinical.consultation_started").count }.by(1)

      expect(response).to redirect_to(practice_appointment_consultation_path(appointment))
      expect(appointment.reload.status).to eq("in_consultation")
      expect(appointment.consultation_started_at).to eq(appointment.encounter.started_at)
      expect(appointment.appointment_status_changes.last.to_status).to eq("in_consultation")
    end

    it "is idempotent when submitted twice" do
      2.times { post practice_appointment_consultation_path(appointment) }

      expect(appointment.reload.encounter).to be_present
      expect(Encounter.where(appointment: appointment).count).to eq(1)
      expect(appointment.appointment_status_changes.where(to_status: "in_consultation").count).to eq(1)
      expect(AuditEvent.where(action: "clinical.consultation_started", auditable: appointment.encounter).count).to eq(1)
    end

    it "does not start a booked appointment" do
      appointment.update!(status: "booked")

      expect {
        post practice_appointment_consultation_path(appointment)
      }.not_to change(Encounter, :count)

      expect(appointment.reload.status).to eq("booked")
    end

    it "rejects an appointment assigned to another clinician" do
      other = create(:staff_member, practice: practice, staff_type: "doctor", access_level: "staff_clinician")
      appointment.update!(clinician: other)

      expect {
        post practice_appointment_consultation_path(appointment)
      }.not_to change(Encounter, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "does not allow administrative staff to start an encounter" do
      clinician.update!(access_level: "senior_staff_admin")

      expect {
        post practice_appointment_consultation_path(appointment)
      }.not_to change(Encounter, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end

end
