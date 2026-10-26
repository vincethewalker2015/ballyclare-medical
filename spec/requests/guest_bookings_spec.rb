require "rails_helper"

RSpec.describe "Guest booking entry", type: :request do
  it "allows visitors to open the guest booking page without signing in" do
    get guest_booking_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Book as a guest")
    expect(response.body).to include("account or password")
    expect(response.body).to include("guest checkout")
  end

  it "does not list practices without online availability" do
    practice = create(:practice, name: "No online appointments")
    create(:staff_member, practice: practice)

    get guest_booking_path

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.css("ul li").map { |item| item.text.squish }).not_to include(practice.name)
  end
end
