module Payments
  class StripeOutageDeclaration
    Unauthorized = Class.new(StandardError)
    InvalidReason = Class.new(StandardError)
    AlreadyActive = Class.new(StandardError)

    DURATION = 30.minutes
    ACTIONS = %w[stripe_outage.activated stripe_outage.deactivated].freeze

    def self.active?(practice:)
      latest = AuditEvent.where(practice: practice, auditable: practice, action: ACTIONS)
        .order(created_at: :desc, id: :desc).first

      latest&.action == "stripe_outage.activated" &&
        latest.created_at > DURATION.ago
    end

    def self.activate!(practice:, actor:, reason:)
      record!(practice: practice, actor: actor, reason: reason,
        action: "stripe_outage.activated")
    end

    def self.deactivate!(practice:, actor:, reason:)
      record!(practice: practice, actor: actor, reason: reason,
        action: "stripe_outage.deactivated")
    end

    def self.record!(practice:, actor:, reason:, action:)
      unless actor&.practice_id == practice.id && actor.senior_administration_access?
        raise Unauthorized, "Only a senior administrator of this practice may declare a Stripe outage"
      end

      raise InvalidReason, "An outage declaration requires a reason" if reason.blank?

      practice.with_lock do
        if action == "stripe_outage.activated" && active?(practice: practice)
          raise AlreadyActive, "A Stripe outage declaration is already active for this practice"
        end

        AuditEvent.create!(
          practice: practice,
          user: actor.user,
          auditable: practice,
          action: action,
          metadata: { reason: reason.strip }
        )
      end
    end

    private_class_method :record!
  end
end
