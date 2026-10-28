module Staff
  class StripeOutagesController < BaseController
    before_action :require_senior_administrator

    def show
      @outage_active = Payments::StripeOutageDeclaration.active?(practice: current_practice)
    end

    def create
      Payments::StripeOutageDeclaration.activate!(
        practice: current_practice,
        actor: current_staff_member,
        reason: params[:reason]
      )
      redirect_to practice_stripe_outage_path, notice: "Stripe outage declared for 30 minutes."
    rescue Payments::StripeOutageDeclaration::InvalidReason
      redirect_to practice_stripe_outage_path, alert: "Enter a reason for the outage declaration."
    rescue Payments::StripeOutageDeclaration::AlreadyActive
      redirect_to practice_stripe_outage_path, alert: "A Stripe outage declaration is already active."
    end

    private

    def require_senior_administrator
      head :forbidden unless current_staff_member.senior_administration_access?
    end
  end
end
