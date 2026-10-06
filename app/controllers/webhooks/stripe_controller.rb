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
      when "refund.updated"
        handle_refund_updated(event.data.object)
      else
        Rails.logger.info(
          "Unhandled Stripe webhook event: #{event.type}"
        )
      end
    end

    def handle_event(event)
      case event.type
      when "payment_intent.succeeded"
        handle_payment_succeeded(event.data.object)
      when "payment_intent.payment_failed"
        handle_payment_failed(event.data.object)
      when "refund.updated"
        handle_refund_updated(event.data.object)
      else
        Rails.logger.info(
          "Unhandled Stripe webhook event: #{event.type}"
        )
      end
    end

    def handle_refund_updated(stripe_refund)
      return unless stripe_refund.status == "succeeded"

      Payments::HandleRefundSucceeded.new(
        stripe_refund: stripe_refund
      ).call
    rescue Payments::HandleRefundSucceeded::RefundNotFound => e
      Rails.logger.warn(
        "Ignoring Stripe refund.updated: #{e.message}"
      )
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

    def handle_payment_failed(payment_intent)
      Payments::HandleFailed.new(
        payment_intent: payment_intent
      ).call
    rescue Payments::HandleFailed::PaymentNotFound => e
      Rails.logger.warn(
        "Ignoring Stripe payment_intent.payment_failed: #{e.message}"
      )
    end
  end
end
