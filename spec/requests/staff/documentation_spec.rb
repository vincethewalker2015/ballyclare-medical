require "rails_helper"

RSpec.describe "Staff user manual", type: :request do
  let(:user) { create(:user) }

  before do
    create(:staff_member, practice: create(:practice), user: user)
  end

  it "renders local illustration images in the staff manual" do
    sign_in user

    get user_manual_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include(
      'src="/docs/images/user_manual/patients-list-illustration.png"'
    )
    expect(response.body).to include("alt=")
  end

  it "renders working contents anchors for manual sections" do
    sign_in user

    get user_manual_path

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML(response.body)
    contents_link = document.at_css('a[href="#booking-an-appointment"]')

    expect(contents_link).to be_present
    expect(document.at_css("h2#booking-an-appointment")).to be_present
    expect(document.at_css('a[href="#getting-started"]')).to be_present
    expect(document.at_css("h2#getting-started")).to be_present
  end

  it "serves a committed illustration to signed-in staff" do
    sign_in user

    get "/docs/images/user_manual/patients-list-illustration.png"

    expect(response).to have_http_status(:success)
    expect(response.media_type).to eq("image/png")
    expect(response.body).to start_with("\x89PNG".b)
  end

  it "requires sign-in to view manual illustrations" do
    get "/docs/images/user_manual/patients-list-illustration.png"

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects paths outside the manual illustration folder" do
    sign_in user

    get "/docs/images/user_manual/..%2Fuser_manual.md"

    expect(response).to have_http_status(:not_found)
  end
end
