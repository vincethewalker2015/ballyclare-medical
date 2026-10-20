module Staff
  class InvitationsController < ApplicationController
    before_action :load_invited_user, only: %i[edit update]

    def edit
    end

    def update
      @user = User.reset_password_by_token(
        reset_password_token: params[:reset_password_token],
        password: params.dig(:user, :password),
        password_confirmation: params.dig(:user, :password_confirmation)
      )

      if @user.errors.empty? && @user.persisted?
        @user.update!(invitation_pending_at: nil)
        sign_in(:user, @user)
        redirect_to root_path, notice: "Your password has been set successfully."
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def load_invited_user
      token = params[:reset_password_token].to_s
      @user = User.with_reset_password_token(token) if token.present?

      return if @user&.invitation_pending_at? && @user.reset_password_period_valid?

      redirect_to new_user_password_path,
        alert: "This invitation link is invalid or has expired. Request a new password link."
    end
  end
end
