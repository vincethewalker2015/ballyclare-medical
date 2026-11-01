require "rails_helper"

RSpec.describe MedicalGroup, type: :model do
  it "requires a name" do
    expect(build(:medical_group, name: nil)).not_to be_valid
  end

  it "restricts deletion while practices belong to it" do
    practice = create(:practice)
    expect(practice.medical_group.destroy).to be false
    expect(MedicalGroup.exists?(practice.medical_group_id)).to be true
  end

  it "keeps independently created practices in separate groups by default" do
    first = create(:practice)
    second = create(:practice)

    expect(first.medical_group_id).not_to eq(second.medical_group_id)
  end

  it "requires each practice to belong to a medical group" do
    practice = build(:practice, medical_group: nil)
    expect(practice).not_to be_valid
  end

  it "rejects a nonexistent medical group at the database boundary" do
    practice = create(:practice)
    expect {
      practice.update_columns(medical_group_id: SecureRandom.uuid)
    }.to raise_error(ActiveRecord::InvalidForeignKey)
  end
end
