require "rails_helper"

RSpec.describe "Staff invitations", type: :request do
  let(:user) { create(:user, invitation_pending_at: Time.current) }
  let(:token) { user.send(:set_reset_password_token) }

  it "shows the dedicated password setup form for a valid invitation" do
    get edit_staff_invitation_path(reset_password_token: token)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Set my password")
    expect(response.body).not_to include("Sign up")
  end

  it "rejects an invalid invitation token" do
    get edit_staff_invitation_path(reset_password_token: "invalid")

    expect(response).to redirect_to(new_user_password_path)
  end

  it "rejects an expired invitation token" do
    token
    user.update!(reset_password_sent_at: 7.hours.ago)

    get edit_staff_invitation_path(reset_password_token: token)

    expect(response).to redirect_to(new_user_password_path)
  end

  it "does not treat a normal password reset as an invitation" do
    user.update!(invitation_pending_at: nil)

    get edit_staff_invitation_path(reset_password_token: token)

    expect(response).to redirect_to(new_user_password_path)
  end

  it "allows invited staff to set a password and signs them in" do
    patch staff_invitation_path, params: {
      reset_password_token: token,
      user: { password: "securepassword123", password_confirmation: "securepassword123" }
    }

    expect(response).to redirect_to(root_path)
    expect(user.reload.invitation_pending_at).to be_nil
    expect(user.valid_password?("securepassword123")).to be(true)
  end

  it "shows errors for mismatched passwords without accepting the invitation" do
    patch staff_invitation_path, params: {
      reset_password_token: token,
      user: { password: "securepassword123", password_confirmation: "differentpassword" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload.invitation_pending_at).to be_present
  end

  it "cannot reuse an accepted invitation token" do
    patch staff_invitation_path, params: {
      reset_password_token: token,
      user: { password: "securepassword123", password_confirmation: "securepassword123" }
    }

    get edit_staff_invitation_path(reset_password_token: token)

    expect(response).to redirect_to(new_user_password_path)
  end
end
