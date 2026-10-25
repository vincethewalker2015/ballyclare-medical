require "rails_helper"

RSpec.describe PatientAccountLink, type: :model do
  let(:practice) { create(:practice) }
  let(:patient) { create(:patient, practice: practice) }
  let(:account) { create(:patient_account) }

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
end
