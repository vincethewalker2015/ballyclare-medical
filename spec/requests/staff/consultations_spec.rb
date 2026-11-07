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

  it "redacts clinical note and patient document form fields from parameter logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter(
      "clinical_note" => { "body" => "Sensitive consultation narrative", "lock_version" => "0" },
      "clinical_document_release" => { "title" => "Private letter title", "body" => "Sensitive patient letter" }
    )

    expect(filtered.dig("clinical_note", "body")).to eq("[FILTERED]")
    expect(filtered.dig("clinical_document_release", "title")).to eq("[FILTERED]")
    expect(filtered.dig("clinical_document_release", "body")).to eq("[FILTERED]")
    expect(filtered.dig("clinical_note", "lock_version")).to eq("0")
  end


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

  describe "draft clinical notes" do
    before do
      appointment.update!(status: "arrived")
      post practice_appointment_consultation_path(appointment)
    end

    it "saves and resumes a draft with audit events" do
      expect {
        patch draft_practice_appointment_consultation_path(appointment),
          params: { clinical_note: { body: "Presenting complaint: headache", lock_version: 0 } }
      }.to change(ClinicalNote, :count).by(1)

      note = appointment.reload.encounter.clinical_notes.last
      expect(note.status).to eq("draft")
      expect(note.body).to include("headache")
      expect(AuditEvent.where(auditable: note, action: "clinical.draft_created")).to exist

      get practice_appointment_consultation_path(appointment)
      expect(response.body).to include("Presenting complaint: headache")
    end

    it "rejects a stale edit without overwriting the current draft" do
      path = draft_practice_appointment_consultation_path(appointment)
      patch path, params: { clinical_note: { body: "Original", lock_version: 0 } }
      patch path, params: { clinical_note: { body: "Revised", lock_version: 0 } }
      expect(appointment.encounter.clinical_notes.last.reload.body).to eq("Revised")

      patch path, params: { clinical_note: { body: "Stale", lock_version: 0 } }
      expect(appointment.encounter.clinical_notes.last.reload.body).to eq("Revised")
      expect(response).to redirect_to(practice_appointment_consultation_path(appointment))
    end

    it "rejects an administrator writing clinical drafts" do
      clinician.update!(access_level: "senior_staff_admin")
      expect {
        patch draft_practice_appointment_consultation_path(appointment),
          params: { clinical_note: { body: "Unauthorised", lock_version: 0 } }
      }.not_to change(ClinicalNote, :count)
      expect(response).to have_http_status(:forbidden)
    end
  end
  describe "signing and completing a consultation" do
    let(:draft_path) { draft_practice_appointment_consultation_path(appointment) }
    let(:sign_path) { sign_and_complete_practice_appointment_consultation_path(appointment) }

    before do
      appointment.update!(status: "arrived")
      post practice_appointment_consultation_path(appointment)
      patch draft_path, params: { clinical_note: { body: "Assessment and plan documented", lock_version: 0 } }
    end

    it "signs the note, closes the encounter, completes the appointment and audits both actions" do
      note = appointment.reload.encounter.clinical_notes.last
      expect {
        post sign_path, params: { clinical_note: { lock_version: note.lock_version } }
      }.to change { AuditEvent.where(action: "clinical.note_signed").count }.by(1)
        .and change { AuditEvent.where(action: "clinical.consultation_completed").count }.by(1)

      expect(response).to redirect_to(practice_appointment_consultation_path(appointment))
      expect(note.reload.status).to eq("signed")
      expect(note.signed_at).to be_present
      expect(appointment.reload.status).to eq("completed")
      expect(appointment.completed_at).to eq(appointment.encounter.reload.ended_at)
      expect(appointment.appointment_status_changes.where(from_status: "in_consultation", to_status: "completed").count).to eq(1)
      get practice_appointment_consultation_path(appointment)
      expect(response.body).to include("Signed consultation note", "Assessment and plan documented")
      expect(response.body).not_to include("Save draft")
    end

    it "rejects stale signatures without changing clinical state" do
      note = appointment.reload.encounter.clinical_notes.last
      post sign_path, params: { clinical_note: { lock_version: note.lock_version + 1 } }
      expect(note.reload.status).to eq("draft")
      expect(appointment.reload.status).to eq("in_consultation")
    end

    it "rejects signing an empty draft" do
      note = appointment.reload.encounter.clinical_notes.last
      patch draft_path, params: { clinical_note: { body: "", lock_version: note.lock_version } }
      note.reload
      post sign_path, params: { clinical_note: { lock_version: note.lock_version } }
      expect(note.reload.status).to eq("draft")
      expect(appointment.reload.status).to eq("in_consultation")
    end

    it "does not sign twice or allow edits after completion" do
      note = appointment.reload.encounter.clinical_notes.last
      post sign_path, params: { clinical_note: { lock_version: note.lock_version } }
      post sign_path, params: { clinical_note: { lock_version: note.lock_version } }
      patch draft_path, params: { clinical_note: { body: "Tampered", lock_version: 0 } }
      expect(note.reload.body).to eq("Assessment and plan documented")
      expect(AuditEvent.where(action: "clinical.note_signed", auditable: note).count).to eq(1)
    end

    it "forbids other clinicians and administrators" do
      note = appointment.reload.encounter.clinical_notes.last
      clinician.update!(access_level: "senior_staff_admin")
      post sign_path, params: { clinical_note: { lock_version: note.lock_version } }
      expect(response).to have_http_status(:forbidden)
      expect(note.reload.status).to eq("draft")
    end
  end
  describe "signed-note amendments" do
    let(:amend_path) { amend_practice_appointment_consultation_path(appointment) }

    before do
      appointment.update!(status: "arrived")
      post practice_appointment_consultation_path(appointment)
      patch draft_practice_appointment_consultation_path(appointment),
        params: { clinical_note: { body: "Original signed assessment", lock_version: 0 } }
      note = appointment.reload.encounter.clinical_notes.last
      post sign_and_complete_practice_appointment_consultation_path(appointment),
        params: { clinical_note: { lock_version: note.lock_version } }
    end

    it "records an attributed, audited append-only amendment and preserves the original" do
      note = appointment.reload.encounter.clinical_notes.find_by!(status: "signed")
      original_timestamp = note.signed_at
      expect {
        post amend_path, params: { clinical_note_amendment: { reason: "Correct medication history", body: "Corrected history" } }
      }.to change(ClinicalNoteAmendment, :count).by(1)
        .and change { AuditEvent.where(action: "clinical.note_amended").count }.by(1)
      amendment = note.amendments.last
      expect(response).to redirect_to(practice_appointment_consultation_path(appointment))
      expect(amendment.author).to eq(clinician)
      expect(amendment.reason).to eq("Correct medication history")
      expect(amendment.body).to eq("Corrected history")
      expect(note.reload.body).to eq("Original signed assessment")
      expect(note.status).to eq("signed")
      expect(note.signed_at).to eq(original_timestamp)
      expect(AuditEvent.where(action: "clinical.note_amended", auditable: amendment, practice: practice)).to exist
      get practice_appointment_consultation_path(appointment)
      expect(response.body).to include("Amendment history", "Original signed assessment", "Corrected history")
    end

    it "rejects missing reason and empty amendments" do
      expect {
        post amend_path, params: { clinical_note_amendment: { reason: " ", body: "Correction" } }
        post amend_path, params: { clinical_note_amendment: { reason: "Correction", body: " " } }
      }.not_to change(ClinicalNoteAmendment, :count)
    end

    it "rejects unsigned and non-completed consultation records" do
      appointment.update!(status: "in_consultation")
      expect {
        post amend_path, params: { clinical_note_amendment: { reason: "Correction", body: "Text" } }
      }.not_to change(ClinicalNoteAmendment, :count)
    end

    it "forbids non-clinical administration and colleagues" do
      other_user = create(:user)
      other = create(:staff_member, user: other_user, practice: practice, staff_type: "doctor", access_level: "staff_clinician")
      sign_out user
      sign_in other_user
      expect {
        post amend_path, params: { clinical_note_amendment: { reason: "Correction", body: "Text" } }
      }.not_to change(ClinicalNoteAmendment, :count)
      expect(response).to have_http_status(:forbidden)

      sign_out other_user
      sign_in user
      clinician.update!(access_level: "senior_staff_admin")
      post amend_path, params: { clinical_note_amendment: { reason: "Correction", body: "Text" } }
      expect(response).to have_http_status(:forbidden)
      expect(ClinicalNoteAmendment.count).to eq(0)
    end

    it "returns not found for another practice's appointment" do
      sibling_appointment = create(:appointment, practice: sibling)
      expect {
        post amend_practice_appointment_consultation_path(sibling_appointment),
          params: { clinical_note_amendment: { reason: "Correction", body: "Text" } }
      }.not_to change(ClinicalNoteAmendment, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "does not show amendments in the patient portal by default" do
      post amend_path, params: { clinical_note_amendment: { reason: "Correction", body: "Internal amended details" } }
      get patient_portal_clinical_documents_path
      expect(response.body).not_to include("Internal amended details")
    end
  end

  describe "releasing patient-facing clinical documents" do
    before do
      appointment.update!(status: "arrived")
      post practice_appointment_consultation_path(appointment)
      patch draft_practice_appointment_consultation_path(appointment),
        params: { clinical_note: { body: "Private internal clinical assessment", lock_version: 0 } }
      note = appointment.reload.encounter.clinical_notes.last
      post sign_and_complete_practice_appointment_consultation_path(appointment),
        params: { clinical_note: { lock_version: note.lock_version } }
    end

    it "releases only explicitly authored patient-facing content and audits the action" do
      expect {
        post release_document_practice_appointment_consultation_path(appointment),
          params: { clinical_document_release: { title: "Visit summary", body: "Follow-up in one week" } }
      }.to change(ClinicalDocumentRelease, :count).by(1)
        .and change { AuditEvent.where(action: "clinical.document_released").count }.by(1)

      release = ClinicalDocumentRelease.last
      expect(release.practice).to eq(practice)
      expect(release.patient).to eq(appointment.patient)
      expect(release.body).to eq("Follow-up in one week")
      expect(release.body).not_to include("Private internal clinical assessment")
    end

    it "rejects release by administrators" do
      clinician.update!(access_level: "senior_staff_admin")
      expect {
        post release_document_practice_appointment_consultation_path(appointment),
          params: { clinical_document_release: { title: "Summary", body: "Advice" } }
      }.not_to change(ClinicalDocumentRelease, :count)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
