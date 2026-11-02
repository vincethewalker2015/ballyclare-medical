require "rails_helper"

RSpec.describe "Patient portal clinical document releases", type: :request do
  let(:group) { create(:medical_group) }
  let(:practice) { create(:practice, medical_group: group) }
  let(:sibling) { create(:practice, medical_group: group) }
  let(:account) { create(:patient_account, confirmed_at: Time.current) }
  let(:patient) { create(:patient, practice: practice) }
  let(:clinician) { create(:staff_member, practice: practice, staff_type: "doctor", access_level: "staff_clinician") }

  def approve_link
    administrator = create(:staff_member, practice: practice,
      staff_type: "administrator", access_level: "staff_admin")
    PatientAccountLink.create!(
      patient_account: account, patient: patient, practice: practice,
      status: "approved", verification_method: "in_person",
      verified_at: Time.current, verified_by: administrator, approved_at: Time.current
    )
  end

  def release_for(patient_record:, clinician_record:, title:, body:)
    encounter = Encounter.create!(
      practice: patient_record.practice, patient: patient_record,
      clinician: clinician_record, encounter_type: "consultation", started_at: 1.day.ago
    )
    ClinicalDocumentRelease.create!(
      practice: patient_record.practice, patient: patient_record,
      encounter: encounter, released_by: clinician_record,
      title: title, body: body, released_at: Time.current
    )
  end

  it "subscribes only the approved patient link to document refreshes" do
    link = approve_link
    sign_in account, scope: :patient_account
    get patient_portal_clinical_documents_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("turbo-cable-stream-source")
    signed_stream = response.parsed_body.at_css("turbo-cable-stream-source")["signed-stream-name"]
    expect(Turbo::StreamsChannel.verified_stream_name(signed_stream)).to eq(
      Turbo::StreamsChannel.send(:stream_name_from, link, :clinical_documents)
    )
    expect(response.body).not_to include("Confidential internal assessment")
  end

  it "broadcasts a refresh to the approved patient link after a release" do
    link = approve_link
    expect(Turbo::StreamsChannel).to receive(:broadcast_refresh_to).with(link, :clinical_documents)
    release_for(patient_record: patient, clinician_record: clinician,
      title: "Aftercare", body: "Patient guidance")
  end

  it "does not broadcast a release to revoked patient connections" do
    link = approve_link
    link.update!(status: "revoked")
    expect(Turbo::StreamsChannel).not_to receive(:broadcast_refresh_to)
    release_for(patient_record: patient, clinician_record: clinician,
      title: "Private release", body: "Patient guidance")
  end

  it "requires a signed-in patient account" do
    get patient_portal_clinical_documents_path
    expect(response).to redirect_to(new_patient_account_session_path)
  end

  it "denies access without an approved link" do
    sign_in account, scope: :patient_account
    get patient_portal_clinical_documents_path
    expect(response).to have_http_status(:forbidden)
  end

  it "shows only explicitly released documents for the linked patient" do
    approve_link
    release_for(patient_record: patient, clinician_record: clinician,
      title: "Released aftercare", body: "Take rest and attend follow-up")
    other_patient = create(:patient, practice: practice)
    release_for(patient_record: other_patient, clinician_record: clinician,
      title: "Other patient secret", body: "Other patient confidential content")
    sibling_clinician = create(:staff_member, practice: sibling, staff_type: "doctor", access_level: "staff_clinician")
    release_for(patient_record: create(:patient, practice: sibling),
      clinician_record: sibling_clinician, title: "Sibling practice secret", body: "Sibling confidential content")

    sign_in account, scope: :patient_account
    get patient_portal_clinical_documents_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Released aftercare", "Take rest and attend follow-up")
    expect(response.body).not_to include("Other patient secret", "Sibling practice secret")
    expect(response.body).not_to include("Other patient confidential content", "Sibling confidential content")
  end

  it "audits approved patient document access without logging document contents" do
    approve_link
    release_for(patient_record: patient, clinician_record: clinician,
      title: "Patient guidance", body: "Sensitive patient instructions")
    sign_in account, scope: :patient_account

    expect {
      get patient_portal_clinical_documents_path
    }.to change { AuditEvent.where(action: "clinical.patient_documents_viewed").count }.by(1)

    event = AuditEvent.where(action: "clinical.patient_documents_viewed").last
    expect(event.practice).to eq(practice)
    expect(event.metadata.to_s).not_to include("Sensitive patient instructions")
  end

  it "does not audit denied patient document access" do
    sign_in account, scope: :patient_account
    expect {
      get patient_portal_clinical_documents_path
    }.not_to change { AuditEvent.where(action: "clinical.patient_documents_viewed").count }
    expect(response).to have_http_status(:forbidden)
  end

  it "does not display internal signed notes without a release" do
    approve_link
    encounter = Encounter.create!(
      practice: practice, patient: patient, clinician: clinician,
      encounter_type: "consultation", started_at: 1.day.ago
    )
    ClinicalNote.create!(
      encounter: encounter, patient: patient, author: clinician,
      note_type: "consultation", body: "Confidential internal assessment"
    )
    sign_in account, scope: :patient_account
    get patient_portal_clinical_documents_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Confidential internal assessment")
    expect(response.body).to include("No clinical documents have been released")
  end

  it "revokes access immediately when the patient connection is revoked" do
    link = approve_link
    release_for(patient_record: patient, clinician_record: clinician,
      title: "Previously released", body: "Previously accessible information")
    sign_in account, scope: :patient_account
    get patient_portal_clinical_documents_path
    expect(response).to have_http_status(:ok)

    link.update!(status: "revoked")
    get patient_portal_clinical_documents_path
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include("Previously accessible information")
  end

  it "does not permit modifying released documents" do
    release = release_for(patient_record: patient, clinician_record: clinician,
      title: "Original", body: "Unchanged")
    expect(release.update(title: "Altered")).to eq(false)
    expect(release.reload.title).to eq("Original")
  end
end
