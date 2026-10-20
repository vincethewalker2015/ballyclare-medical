require "rails_helper"

RSpec.describe "User sign-in and inactive staff", type: :request do
  let(:password) { "SecurePassword123!" }
  let(:user) { create(:user, password: password, password_confirmation: password) }

  it "shows a clear warning for an inactive staff member with valid credentials" do
    create(:staff_member, user: user, active: false)

    post user_session_path, params: { user: { email: user.email, password: password } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Your staff account is inactive")
    expect(response.body).to include("Sign in")
  end

  it "does not disclose inactive status for incorrect credentials" do
    create(:staff_member, user: user, active: false)

    post user_session_path, params: { user: { email: user.email, password: "incorrect" } }

    expect(response.body).not_to include("Your staff account is inactive")
  end

  it "allows an active staff member to sign in" do
    create(:staff_member, user: user, active: true)

    post user_session_path, params: { user: { email: user.email, password: password } }

    expect(response).to have_http_status(:redirect)
  end
end
