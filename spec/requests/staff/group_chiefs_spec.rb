require "rails_helper"

RSpec.describe "Chief of Group appointment", type: :request do
  let(:group) { create(:medical_group) }
  let(:home) { create(:practice, medical_group: group) }
  let(:sibling) { create(:practice, medical_group: group) }
  let(:admin) { create(:user) }
  let(:candidate) { create(:user) }

  before do
    create(:staff_member, user: admin, practice: home,
      staff_type: "administrator", access_level: "senior_staff_admin")
    create(:staff_member, user: candidate, practice: sibling)
    sign_in admin
  end

  it "lets a senior administrator appoint the first Chief and records an audit event" do
    expect {
      patch practice_group_chief_path, params: { user_id: candidate.id }
    }.to change { group.reload.chief_of_group_id }.from(nil).to(candidate.id)
      .and change { AuditEvent.where(action: "medical_group.chief_changed").count }.by(1)

    expect(response).to redirect_to(practice_practices_path)
  end

  it "does not let a senior administrator replace an appointed Chief" do
    group.update!(chief_of_group: candidate)
    patch practice_group_chief_path, params: { user_id: admin.id }

    expect(response).to have_http_status(:forbidden)
    expect(group.reload.chief_of_group).to eq(candidate)
  end

  it "lets the current Chief transfer to another active group member" do
    group.update!(chief_of_group: candidate)
    sign_out admin
    sign_in candidate

    patch practice_group_chief_path, params: { user_id: admin.id }

    expect(response).to redirect_to(practice_practices_path)
    expect(group.reload.chief_of_group).to eq(admin)
  end

  it "rejects candidates from another medical group" do
    outsider = create(:staff_member).user
    patch practice_group_chief_path, params: { user_id: outsider.id }

    expect(group.reload.chief_of_group_id).to be_nil
  end

  it "rejects candidates without active membership" do
    candidate.staff_members.update_all(active: false)
    patch practice_group_chief_path, params: { user_id: candidate.id }

    expect(group.reload.chief_of_group_id).to be_nil
  end

  it "does not let an ordinary staff member appoint the first Chief" do
    sign_out admin
    sign_in candidate
    patch practice_group_chief_path, params: { user_id: candidate.id }

    expect(response).to have_http_status(:forbidden)
    expect(group.reload.chief_of_group_id).to be_nil
  end
end
