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
        handle_payment_succeeded(event.data.object)
      else
        Rails.logger.info(
          "Unhandled Stripe webhook event: #{event.type}"
        )
      end
    end

    def handle_payment_succeeded(payment_intent)
      Payments::HandleSucceeded.new(
        payment_intent: payment_intent
      ).call
    rescue Payments::HandleSucceeded::PaymentNotFound => e
      Rails.logger.warn(
        "Ignoring Stripe payment_intent.succeeded: #{e.message}"
      )
    end
  end
end
