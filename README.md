# README

This README would normally document whatever steps are necessary to get the
application up and running.

## Payments

The application uses a provider-neutral payment model. Stripe is currently
being integrated as the first payment provider.

### Stripe dependency

The Stripe Ruby library is included in the application:

    gem "stripe"

Install dependencies with:

    bundle install

### Payment flow

The payment and booking flow is designed as follows:

1. A patient selects an available appointment slot.
2. The slot is temporarily reserved using an appointment hold.
3. A local pending payment is created.
4. A Stripe PaymentIntent is created for the payment.
5. The Stripe PaymentIntent identifier is stored against the local payment.
6. Payment status changes will be processed using Stripe webhooks.
7. A successful payment will convert the appointment hold into an appointment.

Stripe API calls are isolated behind the payment-provider layer under:

    app/services/payment_providers/

### Testing

Payment service tests can be run with:

    bundle exec rspec spec/services/payments

Stripe provider tests can be run with:

    bundle exec rspec spec/services/payment_providers

Stripe API calls are mocked in the automated test suite and do not make
real Stripe requests.
