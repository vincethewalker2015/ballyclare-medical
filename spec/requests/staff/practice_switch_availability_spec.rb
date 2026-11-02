require "rails_helper"

RSpec.describe "Staff availability after practice switching", type: :request do
  let(:group) { create(:medical_group) }
  let(:home) { create(:practice, medical_group: group) }
  let(:sibling) { create(:practice, medical_group: group) }
  let(:outside) { create(:practice) }
  let(:user) { create(:user) }
  let!(:sibling_clinician) { create(:staff_member, practice: sibling, staff_type: "doctor") }
  let!(:sibling_block) { create(:availability_block, practice: sibling, clinician: sibling_clinician) }
  let!(:outside_block) { create(:availability_block, practice: outside) }

  context "as an administrator" do
    before do
      create(:staff_member, user: user, practice: home, staff_type: "administrator", access_level: "staff_admin")
      sign_in user
      patch practice_selection_path, params: { practice_id: sibling.id }
      expect(response).to redirect_to(practice_appointments_path)
    end

    it "shows the selected practice's availability" do
      get practice_availability_blocks_path

      expect(response).to have_http_status(:ok)
    end

    it "does not allow editing another group's availability" do
      get edit_practice_availability_block_path(outside_block)

      expect(response).to have_http_status(:not_found)
    end

    it "does not allow cancelling another group's availability" do
      patch cancel_practice_availability_block_path(outside_block)

      expect(response).to have_http_status(:not_found)
    end
  end

  context "as a clinician without a local membership" do
    before do
      create(:staff_member, user: user, practice: home, staff_type: "doctor", access_level: "staff_clinician")
      sign_in user
      patch practice_selection_path, params: { practice_id: sibling.id }
      expect(response).to redirect_to(practice_appointments_path)
    end

    it "cannot edit another clinician's availability" do
      get edit_practice_availability_block_path(sibling_block)

      expect(response).to have_http_status(:forbidden)
    end

    it "cannot cancel another clinician's availability" do
      patch cancel_practice_availability_block_path(sibling_block)

      expect(response).to have_http_status(:forbidden)
    end
  end

  context "as a clinician with a local membership" do
    let!(:home_membership) do
      create(:staff_member, user: user, practice: home, staff_type: "doctor", access_level: "staff_clinician")
    end
    let!(:local_membership) do
      create(:staff_member, user: user, practice: sibling, staff_type: "doctor", access_level: "staff_clinician")
    end
    let!(:own_block) { create(:availability_block, practice: sibling, clinician: local_membership) }

    before do
      sign_in user
      patch practice_selection_path, params: { practice_id: sibling.id }
      expect(response).to redirect_to(practice_appointments_path)
    end

    it "can edit their own availability in the selected practice" do
      get edit_practice_availability_block_path(own_block)

      expect(response).to have_http_status(:ok)
    end

    it "cannot edit another clinician's availability in the selected practice" do
      get edit_practice_availability_block_path(sibling_block)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
