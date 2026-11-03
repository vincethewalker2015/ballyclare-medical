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

end
