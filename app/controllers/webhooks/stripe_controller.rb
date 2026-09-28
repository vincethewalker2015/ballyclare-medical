module Webhooks
  class StripeController < ApplicationController
    skip_forgery_protection

    def create
      event = construct_event

      handle_event(event)

      head :ok
    rescue JSON::ParserError, Stripe::SignatureVerificationError
      head :bad_request
    end

    private

    def construct_event
      Stripe::Webhook.construct_event(
        request.raw_post,
        request.headers["Stripe-Signature"],
        ENV["STRIPE_WEBHOOK_SECRET"]
      )
    end

    def handle_event(event)
      case event.type
      when "payment_intent.succeeded"
        Payments::HandleSucceeded.new(
          payment_intent: event.data.object
        ).call
      else
        Rails.logger.info(
          "Unhandled Stripe webhook event: #{event.type}"
        )
      end
    end
  end
end
