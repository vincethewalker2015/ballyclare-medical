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

### Local background jobs and live refund updates

The development and production job adapters currently differ:

- **Development:** `config/environments/development.rb` does not select Solid Queue,
  so Rails uses its configured default Active Job adapter. Refund jobs have been
  observed running as `Async(default)` in local development.
- **Production:** `config/environments/production.rb` explicitly selects
  `:solid_queue`, backed by the production `queue` database.

Do not assume that starting `bin/jobs` makes development jobs run through
Solid Queue. Check the adapter Rails is actually using:

```bash
bin/rails runner 'puts ActiveJob::Base.queue_adapter.class.name'
```

To run the Solid Queue supervisor locally for development or debugging,
the queue tables must first exist in the development database. On a fresh
local setup, `bin/jobs start` may otherwise fail with
`PG::UndefinedTable: solid_queue_processes`.

The current development database configuration has no separate `queue`
database or `db:queue:prepare` task. To initialise the included queue schema
in the **local development database only**, run:

```bash
bin/rails runner 'load Rails.root.join("db/queue_schema.rb")'
```

**Caution:** Loading this schema recreates Solid Queue tables. Do not use this
command as a routine startup step or against a database containing queue
history you need to preserve.

Verify that the tables exist:

```bash
bin/rails runner 'puts SolidQueue::Record.connection.data_source_exists?("solid_queue_processes")'
```

Then, in a separate terminal, start the supervisor if needed:

```bash
bin/jobs start
```

For local Stripe payment and refund testing, keep Rails running and start a
Stripe CLI listener in another terminal:

```bash
stripe listen \
  --events payment_intent.succeeded,payment_intent.payment_failed,payment_intent.canceled,refund.created,refund.updated,refund.failed,charge.refunded \
  --forward-to http://localhost:3000/webhooks/stripe
```

Use the listener's `whsec_` signing secret as `STRIPE_WEBHOOK_SECRET`
in `.env.development`, and restart Rails after changing it. The webhook
controller currently **handles** `payment_intent.succeeded`,
`payment_intent.payment_failed` and successful `refund.updated` events;
other forwarded event types may be logged as unhandled. Forwarding them
does not imply application support for them.

After staff cancel a paid appointment, the system voids active appointment
charges, requests a refund asynchronously and updates local refund records
from Stripe's webhook. The staff appointment page subscribes to a Turbo
Stream and automatically refreshes its refund messages and financial
summary when the refund status changes.

In development, `config/cable.yml` uses the `async` Action Cable adapter,
which only broadcasts within a single process. Live updates observed with
a webhook delivered to the Rails web process do not prove that broadcasts
from a separate worker process will reach that same browser. Production is
configured to use Solid Cable for cross-process delivery. Validate
cross-process updates separately if switching the development job adapter.

For regression tests covering refunds and the staff appointment page:

```bash
bundle exec rspec spec/models/refund_spec.rb spec/requests/practice/appointments_spec.rb spec/services/appointments/change_status_spec.rb
```

## Practice administration: initial administrator setup

The following procedure is for authorised platform operators and developers,
not practice staff. The staff-facing explanation is in
[`docs/user_manual.md`](docs/user_manual.md).

### Provisioning the first Senior Staff Admin (platform operators)

**Platform operator procedure (currently via Rails console):**

1. Create the practice and intended administrator's `User` account through
   an authorised setup process, or identify existing records.
2. Open an authorised Rails console for the intended environment.
3. Locate the correct `Practice` and `User` records using trusted
   identifiers; verify both before continuing.
4. Invoke the bootstrap service:

   ```ruby
   practice = Practice.find("PRACTICE_UUID")
   user = User.find_by!(email: "admin@example.com")

   Practices::BootstrapSeniorStaffAdmin.new(
     practice: practice,
     user: user
   ).call
   ```

The service creates an administrator-type staff membership with
`senior_staff_admin` access. It operates only when the practice has **no
existing staff members**. If anyone is already registered with the practice,
it raises `Practices::BootstrapSeniorStaffAdmin::AlreadyProvisioned` instead
of granting privileges. Concurrent attempts are protected by a database
lock. Do not bypass this restriction by changing access levels manually.

**Security:** Do not use shared accounts, hardcoded temporary passwords or
public self-registration to grant senior permissions. The bootstrap service
does **not** create a user or send an invitation. Ordinary staff accounts can now receive Devise password-setting instructions
when created through the staff UI; initial senior bootstrap does not send them. Avoid putting real patient or
staff credentials in application logs or documentation.


### Staff invitation email configuration

The staff creation form at `/practice/staff_members/new` is available to
`staff_admin` and `senior_staff_admin` memberships. A new email address
creates a `User` and `StaffMember` in one transaction. On successful
creation, the controller calls Devise's
`send_reset_password_instructions` for **newly created accounts only**.
Existing accounts retain their password and do not receive this email.
No invitation is sent if validation prevents staff membership creation.

Before enabling staff onboarding outside a test environment:

1. Configure a verified sender address in
   `config/initializers/devise.rb` (currently a placeholder).
2. Configure a real outgoing email delivery service for production in
   `config/environments/production.rb` and set a public HTTPS host in
   `config.action_mailer.default_url_options` (currently `example.com`).
   Keep SMTP credentials in environment variables or Rails credentials;
   never commit them.
3. Verify email delivery and the complete password-setting link flow in
   a deployed staging environment. Confirm reset links point to the
   correct application host and that the new user can sign in.
4. Ensure delivery failures are monitored. The application does not yet
   provide an administrator-facing resend invitation action.

The test environment uses Action Mailer's `:test` delivery method and
does not send real email. Run the staff request suite with:

```bash
bundle exec rspec spec/requests/practice/staff_members_spec.rb
```

**Deployment blocker:** Production SMTP, sender identity and application
host are not configured in the repository. Do not present staff invitations
as operational in production until those are set up and verified.
