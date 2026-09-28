stripe_secret_key = ENV["STRIPE_SECRET_KEY"]

if stripe_secret_key.present?
  Stripe.api_key = stripe_secret_key
elsif !Rails.env.test?
  Rails.logger.warn("STRIPE_SECRET_KEY is not configured")
end
