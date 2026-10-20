require "rails_helper"

RSpec.describe "Privileged staff administration", type: :request do
  let(:practice) { create(:practice) }
  let(:user) { create(:user) }
  let!(:administrator) do
    create(:staff_member, practice: practice, user: user,
      staff_type: "administrator", access_level: "staff_admin")
  end
  let!(:senior) do
    create(:staff_member, practice: practice,
      staff_type: "administrator", access_level: "senior_staff_admin")
  end
  let!(:ordinary) do
    create(:staff_member, practice: practice,
      staff_type: "administrator", access_level: "staff")
  end

  before { sign_in user }

  it "forbids a Staff Admin from editing a privileged staff account" do
    get edit_practice_staff_member_path(senior)
    expect(response).to have_http_status(:forbidden)

    patch practice_staff_member_path(senior), params: {
      staff_member: { first_name: "Changed" }
    }
    expect(response).to have_http_status(:forbidden)
    expect(senior.reload.first_name).not_to eq("Changed")
  end

  it "allows a Staff Admin to edit an ordinary staff account" do
    get edit_practice_staff_member_path(ordinary)
    expect(response).to have_http_status(:success)
  end

  it "hides privileged edit links while retaining ordinary staff edit links" do
    get practice_staff_members_path
    links = response.parsed_body.css("a").map { |link| link["href"] }
    expect(links).not_to include(edit_practice_staff_member_path(senior))
    expect(links).to include(edit_practice_staff_member_path(ordinary))
  end
end
