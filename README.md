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

### Stripe configuration

Development credentials are loaded using `dotenv-rails`.

Copy the example environment configuration:

    cp .env.example .env.development

Add your Stripe test secret key:

    STRIPE_SECRET_KEY=your_test_secret_key

Do not commit `.env` or `.env.development` files containing credentials.

## Stripe development setup

Payments use Stripe PaymentIntents. Local development uses Stripe test/sandbox credentials and the Stripe CLI for webhook forwarding.

### Environment variables

Create `.env.development` with:

    STRIPE_SECRET_KEY=...
    STRIPE_PUBLISHABLE_KEY=...
    STRIPE_WEBHOOK_SECRET=...

Never commit `.env` or `.env.development`. `.env.example` should contain empty placeholders only.

The Stripe secret and publishable keys must belong to the same Stripe sandbox used by the Stripe CLI.

### Verify the Stripe sandbox

Start a Rails console:

    bin/rails console

Verify the Stripe credentials:

    Stripe::Account.retrieve.id

A more reliable check is to create an unconfirmed PaymentIntent in Rails:

    intent = Stripe::PaymentIntent.create(
      amount: 1234,
      currency: "gbp"
    )

    intent.id

Then, from a normal terminal, retrieve that exact PaymentIntent:

    stripe payment_intents retrieve <PAYMENT_INTENT_ID>

The CLI must be able to retrieve it. If Stripe returns `resource_missing`, Rails and the Stripe CLI are operating in different Stripe accounts or sandboxes.

A successful `stripe trigger` by itself does not prove that Rails and the CLI are using the same Stripe resource space.

### Local webhooks

Authenticate the Stripe CLI:

    stripe login

Start webhook forwarding:

    stripe listen \
      --events payment_intent.succeeded \
      --forward-to http://localhost:3000/webhooks/stripe

The listener prints a webhook signing secret beginning with `whsec_`.

Set that value in `.env.development`:

    STRIPE_WEBHOOK_SECRET=...

Restart Rails after changing the webhook secret.

The signing secret belongs to the current listener configuration and may change when the listener is restarted.

Test webhook forwarding:

    stripe trigger payment_intent.succeeded

A healthy setup should show:

    --> payment_intent.succeeded [evt_...]
    <-- [200] POST http://localhost:3000/webhooks/stripe [evt_...]

### Payment booking flow

The application creates a local pending payment associated with an appointment hold.

It then creates a Stripe PaymentIntent using the local payment's idempotency key.

When Stripe sends `payment_intent.succeeded`, the application:

1. verifies the Stripe webhook signature;
2. locates the local payment;
3. validates the received amount and currency;
4. records the successful payment;
5. locks the appointment slot;
6. creates the appointment;
7. moves the payment from the hold to the appointment; and
8. removes the appointment hold.

If Stripe has successfully taken payment but the appointment can no longer be created, the payment is marked `requires_refund`.

Webhook processing is idempotent. A payment already marked `requires_refund` is not sent through booking again.

### Tests

Stripe API calls are mocked in the automated test suite. Running the test suite does not create real Stripe PaymentIntents or charges.

Run:

    bundle exec rspec
