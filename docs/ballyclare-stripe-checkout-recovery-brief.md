# Ballyclare Medical — Stripe booking checkout recovery implementation brief

## Purpose
Apply the Mercanti One payment recovery improvements to `vincethewalker2015/ballyclare-medical` without copying its branding or changing established booking/payment safety rules.

## Observed issue
A patient appointment hold creates a local payment and a Stripe PaymentIntent. Stripe may report `requires_payment_method` (for example, when the card form was abandoned), while the local payment remains `processing`. A second checkout POST redirects to “payment verification pending,” preventing the patient from completing the original attempt. The staff reconciliation queue hides payments until 15 minutes after their last update.

## Required changes
1. On a repeat payment POST for an existing `pending`/`processing` payment, redirect to a dedicated GET checkout route. **Do not create a second local Payment or Stripe PaymentIntent.**
2. For a valid, unexpired hold, retrieve the **existing** PaymentIntent by the stored `provider_payment_id`. Check ID, `metadata.payment_id`, amount, and currency against the local payment. Never trust patient-supplied payment IDs or secrets.
3. Only render the Stripe Payment Element with the retrieved `patient_secret` for a safely resumable Stripe status such as `requires_payment_method` or `requires_confirmation`. For `succeeded`, invoke the existing success reconciliation/booking completion; for `canceled`, invoke the existing failure handler; for other states, show verification pending. Stripe failures should not create another charge.
4. Add “Resume secure payment” to the hold page when an unresolved payment has a known PaymentIntent and the hold has not expired. Preserve the no-new-payment restriction when the reference is unknown.
5. Show all unresolved Stripe booking payments to authorized staff immediately, while marking those whose last update exceeds 15 minutes as **overdue**. Keep staff authorization and practice isolation.
6. Preserve the existing Stripe webhook handlers, idempotency keys, appointment hold expiry, amount/currency checks, duplicate-charge prevention, and refund-required handling. Never turn a failed/abandoned payment into a confirmed appointment.

## Important edge case
Review the existing `ReconcileStripeStatus` behaviour: if it marks `requires_payment_method` as locally `failed` during a routine payment-status GET, the user may lose the ability to resume the same PaymentIntent. Decide explicitly whether a still-valid hold should remain resumable. Avoid changing global reconciliation semantics without tests for guest bookings, webhook retries, expiry, and races.

## Tests to add or update
- Existing Stripe intent is reused after repeat POST/checkout GET; payment count remains one.
- `requires_payment_method` renders Stripe checkout for the **same** intent.
- `processing`/unknown Stripe status does not reopen checkout.
- `succeeded` reconciles safely, exactly once.
- Expired holds, revoked patient access, cross-practice IDs, mismatched Stripe metadata/amount/currency cannot resume.
- Stripe API errors do not start a new charge.
- Staff sees recent and overdue unresolved payments; basic staff and other practices cannot access them.
- Existing cancellation and webhook idempotency tests continue to pass.

## Operational validation
Use Stripe test keys and a test payment; inspect the PaymentIntent status in Stripe, verify the same intent ID is reused, and confirm a successful payment creates one booking. Do not manually edit payment statuses. Run the full RSpec suite and the app's frontend build.

## Reference
Mercanti One branch: `mercantiworld/mercanti-one`, `rebranding-interface-redesign`. Adapt behaviour, not names, views, routes, or CSS classes.