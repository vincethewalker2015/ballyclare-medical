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
      --events payment_intent.succeeded,refund.updated \
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

### Refund flow

If Stripe successfully takes payment but the appointment cannot be created, the local payment is marked `requires_refund`.

Refunds are represented by separate local refund records. This preserves the relationship between the original payment and any subsequent refund activity.

A refund:

1. belongs to the original payment;
2. records the amount and currency being refunded;
3. has its own idempotency key;
4. is initially created with a `pending` status;
5. is submitted to Stripe through the payment-provider layer;
6. records the Stripe refund identifier; and
7. is updated when Stripe confirms the refund result.

Stripe refund creation is implemented under:

    app/services/payment_providers/stripe_provider/create_refund.rb

Local refund creation and successful-refund handling are implemented under:

    app/services/payments/

Refund creation supports partial refunds. Refunds with `pending`, `processing` or `succeeded` status count towards the amount already allocated for refund, preventing the cumulative refund amount from exceeding the original payment amount.

The payment row is locked while the refundable amount is calculated and the local refund is created. This prevents concurrent refund requests from independently allocating the same refundable balance.

Stripe refund requests use the local refund's idempotency key. If a Stripe request fails before the local refund is updated, the same local refund can therefore be retried without generating a new idempotency key.

### Refund webhooks

Local development should listen for both successful payment events and refund updates:

    stripe listen \
      --events payment_intent.succeeded,refund.updated \
      --forward-to http://localhost:3000/webhooks/stripe

When Stripe sends a successful `refund.updated` event, the application:

1. verifies the Stripe webhook signature;
2. locates the local refund using the Stripe refund identifier;
3. validates the refund amount and currency;
4. marks the local refund as `succeeded`; and
5. records the refund completion time.

Successful refund webhook processing is idempotent. Reprocessing the same successful refund does not replace the original `refunded_at` value.

Refund updates that have not reached the successful state are currently ignored by the webhook handler.

### Appointment hold history

Appointment slots can have multiple appointment holds over their lifetime.

Only an active, unexpired hold prevents another patient from holding the slot. Once a hold expires, the slot may be held again provided that it has not been booked.

Expired holds are retained rather than automatically destroyed. This is important because payments may reference an expired hold as part of the financial and booking history.

Appointment hold creation locks the appointment slot row before checking for an existing appointment or active hold. This serializes competing hold attempts through the application booking workflow.

The database therefore retains historical holds while allowing a slot to be reused after an earlier hold expires.

### Stripe sandbox refund verification

The payment and refund workflow has also been exercised against the Stripe sandbox.

The verified failure path is:

    appointment hold created
        ↓
    Stripe PaymentIntent created
        ↓
    appointment hold expires
        ↓
    Stripe payment succeeds
        ↓
    payment_intent.succeeded webhook received
        ↓
    appointment creation rejected
        ↓
    payment marked requires_refund
        ↓
    local refund created
        ↓
    Stripe refund created
        ↓
    refund.updated webhook received
        ↓
    local refund marked succeeded

This verifies that a successful Stripe payment does not create an appointment from an expired hold and that the resulting refund can complete through the Stripe webhook workflow.

The original payment currently remains `requires_refund` after its associated refund succeeds. Refund completion is represented by the refund record itself. Payment-level representation of full and partial refund state is a separate lifecycle concern and should not be inferred solely from the payment status.

## Development setup

### Create a development staff user

A fresh development database may not contain any roles or staff users. To access the staff-facing application, create a development user and associate it with a practice.

Start the Rails console:

```bash
bin/rails console
```

Check the available practices:

```ruby
Practice.pluck(:id, :name)
```

Create the standard staff roles if they do not already exist:

```ruby
%w[administrator doctor nurse].each do |name|
  Role.find_or_create_by!(name: name)
end
```

Select the practice you want the development user to access:

```ruby
practice = Practice.first
```

Create a user. Choose your own local development password:

```ruby
user = User.find_or_initialize_by(email: "admin@demo-medical.test")

if user.new_record?
  user.password = "YOUR_LOCAL_DEV_PASSWORD"
  user.password_confirmation = "YOUR_LOCAL_DEV_PASSWORD"
  user.save!
end
```

Give the development user all currently defined roles:

```ruby
Role.find_each do |role|
  UserRole.find_or_create_by!(
    user: user,
    role: role
  )
end
```

Create the staff membership:

```ruby
StaffMember.find_or_create_by!(
  user: user,
  practice: practice
) do |staff|
  staff.staff_type = "administrator"
  staff.default_appointment_duration = 30
end
```

Verify the setup:

```ruby
user.reload

user.roles.pluck(:name)
user.staff_members.map { |staff| [staff.practice.name, staff.staff_type] }
```

For a max-access development account, the roles should include:

```ruby
["administrator", "doctor", "nurse"]
```

The staff membership should show the selected practice and administrator staff type, for example:

```ruby
[["Demo Medical Practice", "administrator"]]
```

Exit the Rails console:

```ruby
exit
```

The user can then sign in at:

```text
/users/sign_in
```

and access the staff application at:

```text
/practice/appointments
```

> **Development only:** Never commit real passwords, API keys, payment credentials, or production credentials to the repository.
>
> `StaffMember#staff_type` and `Role` represent different concepts. A staff member's type describes their staff identity within a practice, while roles are used for authorization. The development account above intentionally receives all currently defined roles to make local development and testing easier.
>
> A `User` can have multiple `StaffMember` records and may therefore be associated with multiple practices. The current staff UI uses a temporary single-practice context. Explicit practice selection should be used when multi-practice staff access is implemented.
