require "rails_helper"

RSpec.describe PatientAccountLink, type: :model do
  let(:practice) { create(:practice) }
  let(:patient) { create(:patient, practice: practice) }
  let(:account) { create(:patient_account) }

  it "broadcasts a portal refresh when an approved link is first created" do
    account.confirm
    staff = create(:staff_member, practice: practice, access_level: "staff_admin")

    expect(Turbo::StreamsChannel).to receive(:broadcast_refresh_to)
      .with(account, :portal_access)

    described_class.create!(
      practice: practice, patient: patient, patient_account: account,
      status: "approved", verified_by: staff,
      verification_method: "in_person", verified_at: Time.current,
      approved_at: Time.current
    )
  end

  it "does not broadcast a portal approval refresh for a pending link" do
    expect(Turbo::StreamsChannel).not_to receive(:broadcast_refresh_to)
    described_class.create!(practice: practice, patient: patient, patient_account: account)
  end

  it "keeps a newly created link pending" do
    link = described_class.create!(practice: practice, patient: patient, patient_account: account)
    expect(link.status).to eq("pending")
    expect(described_class.approved).not_to include(link)
  end

  it "rejects a patient from a different practice" do
    link = described_class.new(practice: practice, patient: create(:patient), patient_account: account)
    expect(link).not_to be_valid
  end

  it "requires a confirmed account for approval" do
    staff = create(:staff_member, practice: practice, access_level: "staff_admin")
    link = described_class.new(practice: practice, patient: patient,
      patient_account: account, status: "approved", verified_by: staff,
      verification_method: "in_person", verified_at: Time.current, approved_at: Time.current)
    expect(link).not_to be_valid
    account.confirm
    expect(link).to be_valid
  end

  it "rejects approval from another practice" do
    account.confirm
    staff = create(:staff_member, access_level: "staff_admin")
    link = described_class.new(practice: practice, patient: patient,
      patient_account: account, status: "approved", verified_by: staff,
      verification_method: "in_person", verified_at: Time.current, approved_at: Time.current)
    expect(link).not_to be_valid
  end
  it "allows revocation after the verifying Chief transfers ownership" do
    account.confirm
    chief = create(:user)
    chief_membership = create(:staff_member, practice: practice, user: chief,
      staff_type: "doctor", access_level: "staff_clinician")
    replacement = create(:user)
    create(:staff_member, practice: practice, user: replacement,
      staff_type: "doctor", access_level: "staff_clinician")
    practice.medical_group.update!(chief_of_group: chief)
    link = described_class.create!(
      practice: practice, patient: patient, patient_account: account,
      status: "approved", verified_by: chief_membership,
      verification_method: "in_person", verified_at: Time.current,
      approved_at: Time.current
    )
    practice.medical_group.update!(chief_of_group: replacement)

    expect { link.update!(status: "revoked") }.to change { link.reload.status }
      .from("approved").to("revoked")
    expect(link.verified_by).to eq(chief_membership)
  end

  it "rejects replacing a historical verifier with an unauthorised staff member" do
    account.confirm
    original = create(:staff_member, practice: practice, access_level: "staff_admin")
    outsider = create(:staff_member, access_level: "staff_admin")
    link = described_class.create!(
      practice: practice, patient: patient, patient_account: account,
      status: "approved", verified_by: original,
      verification_method: "in_person", verified_at: Time.current,
      approved_at: Time.current
    )

    expect(link.update(verified_by: outsider)).to eq(false)
    expect(link.errors[:verified_by]).to be_present
    expect(link.reload.verified_by).to eq(original)
  end

  it "rejects reinstating a revoked link when its former verifier has lost authority" do
    account.confirm
    staff = create(:staff_member, practice: practice, access_level: "staff_admin")
    link = described_class.create!(
      practice: practice, patient: patient, patient_account: account,
      status: "approved", verified_by: staff,
      verification_method: "in_person", verified_at: Time.current,
      approved_at: Time.current
    )
    link.update!(status: "revoked")
    staff.update!(active: false)

    expect(link.update(status: "approved")).to eq(false)
    expect(link.errors[:verified_by]).to be_present
    expect(link.reload.status).to eq("revoked")
  end

  it "rejects an inactive verifier without a matching approved registration" do
    account.confirm
    reviewer = create(:staff_member, practice: practice,
      access_level: "staff_admin", active: false)
    link = described_class.new(
      practice: practice, patient: patient, patient_account: account,
      status: "approved", verified_by: reviewer,
      verification_method: "in_person", verified_at: Time.current,
      approved_at: Time.current
    )

    expect(link).not_to be_valid
    expect(link.errors[:verified_by]).to be_present
  end

  it "rejects historical verification when the registration approver is no longer authorised" do
    account.confirm
    reviewer = create(:staff_member, practice: practice, access_level: "staff_admin")
    approver = create(:staff_member, practice: practice, access_level: "senior_staff_admin")
    verified_at = Time.current
    approved_at = Time.current
    PatientRegistrationRequest.create!(
      practice: practice, patient_account: account,
      review_status: "approved", patient_route: "new_patient",
      reviewed_by: reviewer, approved_by: approver,
      identity_verified_at: verified_at, approved_at: approved_at,
      verification_method: "in_person"
    )
    reviewer.update!(active: false)
    approver.update!(active: false)

    link = described_class.new(
      practice: practice, patient: patient, patient_account: account,
      status: "approved", verified_by: reviewer,
      verification_method: "in_person", verified_at: verified_at,
      approved_at: approved_at
    )

    expect(link).not_to be_valid
    expect(link.errors[:verified_by]).to be_present
  end

  it "rejects historical verification with altered identity-check details" do
    account.confirm
    reviewer = create(:staff_member, practice: practice, access_level: "staff_admin")
    approver = create(:staff_member, practice: practice, access_level: "senior_staff_admin")
    verified_at = 1.day.ago
    approved_at = Time.current
    PatientRegistrationRequest.create!(
      practice: practice, patient_account: account,
      review_status: "approved", patient_route: "new_patient",
      reviewed_by: reviewer, approved_by: approver,
      identity_verified_at: verified_at, approved_at: approved_at,
      verification_method: "in_person"
    )
    reviewer.update!(active: false)

    link = described_class.new(
      practice: practice, patient: patient, patient_account: account,
      status: "approved", verified_by: reviewer,
      verification_method: "approved_remote", verified_at: verified_at,
      approved_at: approved_at
    )

    expect(link).not_to be_valid
    expect(link.errors[:verified_by]).to be_present
  end

  it "rejects historical verification for the wrong existing patient" do
    account.confirm
    reviewer = create(:staff_member, practice: practice, access_level: "staff_admin")
    approver = create(:staff_member, practice: practice, access_level: "senior_staff_admin")
    selected_patient = create(:patient, practice: practice)
    verified_at = Time.current
    approved_at = Time.current
    PatientRegistrationRequest.create!(
      practice: practice, patient_account: account,
      review_status: "approved", patient_route: "existing_patient",
      selected_patient: selected_patient,
      reviewed_by: reviewer, approved_by: approver,
      identity_verified_at: verified_at, approved_at: approved_at,
      verification_method: "in_person"
    )
    reviewer.update!(active: false)

    link = described_class.new(
      practice: practice, patient: patient, patient_account: account,
      status: "approved", verified_by: reviewer,
      verification_method: "in_person", verified_at: verified_at,
      approved_at: approved_at
    )

    expect(link).not_to be_valid
    expect(link.errors[:verified_by]).to be_present
  end

end
