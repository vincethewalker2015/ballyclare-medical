# Ballyclare Medical User Manual

This guide is intended for reception, administrative and clinical staff using
Ballyclare Medical. It is being expanded as new features become available.

## Contents

- [Getting Started](#getting-started)
- [Signing In](#signing-in)
- [Patients](#patients)
- [Appointment Diary](#appointment-diary)
- [Booking an Appointment](#booking-an-appointment)
- [Cancelling an Appointment](#cancelling-an-appointment)
- [Payments and Refunds](#payments-and-refunds)
- [Stripe Booking Payment Reconciliation](#stripe-booking-payment-reconciliation)
- [Clinician Availability](#clinician-availability)
- [User and Staff Administration](#user-and-staff-administration)
- [Troubleshooting](#troubleshooting)

## Getting Started

Ballyclare Medical supports day-to-day practice operations, including patients,
clinician availability, appointments and payments. Some clinical and
administrative features are still under development.

## Signing In

Sign in using your individual staff account and password. New staff
members receive password-setting instructions when an administrator
creates their account, provided outgoing email is configured. If you
cannot remember your password, use **Forgot password?** on the sign-in
page. Never share account credentials.

## Patients

Authorised operational staff can open **Patients** to search or browse
records for their own practice, register a new patient, and view or edit
existing patient details. See [Patient records](#patient-records) below
for the registration fields and illustrated instructions.

## Online patient registration: current process

This feature is still being developed. The current steps are:

1. A person creates an online patient account using an email address and password.
2. The application sends an email confirmation link. In development this can be viewed in Letter Opener.
3. After clicking the link, the person can sign in to the patient portal welcome page.

**Email confirmation only establishes access to the email inbox. It does not verify identity or connect the account to a clinical patient record.** No medical information is available to the account holder yet.

### What staff should do now

There is not yet a staff approval screen or account-linking process. Do not attempt to link accounts by matching email addresses or manually changing database records. Continue to use the existing authorised patient and appointment workflows. If a patient asks about access to their records online, explain that the feature is not yet available.

### Planned next steps (not implemented)

The practice will identify the correct patient record, verify the person's identity, explicitly approve the account connection and notify the patient when their access is ready. The system will need to record the approving staff member and verification details. These steps must be implemented and tested before clinical records can be exposed in the portal.

Patients, including one-off patients, can have clinical records and staff-booked appointments without an online account. Guest online booking is a separate planned feature.

## Appointment Diary

All active staff can view the appointment diary and open appointment details.
Basic Staff have read-only access: they cannot book appointments, change
appointment statuses, manage patients or availability, or take payments.
Staff Admins, Staff Clinicians and Senior Staff Admins can perform these
operational tasks.

## Booking an Appointment

Staff Admins, Staff Clinicians and Senior Staff Admins can book appointments
on behalf of patients. Basic Staff can view the diary but cannot book.

1. Open **Appointments** and select **Book appointment**.
2. In the **Patient** field, start with **Select patient**. Click the field
   to see up to five patients, or type a name or patient number to search.
   Choose the correct matching patient from the results. Use the up/down
   arrow keys and **Enter** to choose a result, or **Escape** to close the
   suggestions. The search only returns patients in your practice.
3. Select a **Clinician** (doctor or nurse).
4. Choose the **Appointment date**. Available appointments for that
   clinician and date appear below.
5. Select an available appointment time.
6. Optionally enter the **Reason for appointment**.
7. Review the **Consultation fee** on the booking form. Practice administrators
   configure fees by clinician type; the relevant price is applied automatically.
8. Select **Book appointment**. The system creates the appointment and
   its initial charge, then opens the appointment details.

**Payment is optional for staff-assisted bookings.** The appointment can
remain booked with an outstanding balance. Authorised staff may then take
payment from the appointment page; a failed optional payment does not undo
the already-created appointment.

If the chosen time has become unavailable, choose another available slot.
The server checks availability again when the booking is submitted.

The existing backend also supports temporary appointment holds for
payment-before-booking workflows. A patient-facing self-booking portal is
**planned** and should not be confused with the current staff booking page.

## Cancelling an Appointment

Open the appointment and use the available status controls to cancel it.
Cancellation is blocked while a payment is pending or processing; wait for
the payment to reach a final state before trying again.

When cancellation succeeds, any active consultation charge is voided.
The original charge remains in the appointment's financial history.

If a successful payment has been collected, the system also requests a
refund for the amount not already covered by completed or in-progress
refunds. Staff do not need to initiate the standard cancellation refund
separately.

## Payments and Refunds

### Viewing payments and charges

The appointment page shows a financial summary with:

- **Charges** — total active charges, excluding voided charges.
- **Payments** — successful payments received.
- **Refunds** — refunds confirmed as successful.
- **Outstanding balance** — charges minus successful payments plus
  successful refunds.

A negative outstanding balance can appear temporarily after a paid
appointment is cancelled and its charge is voided, before the refund
has been confirmed. It should return to zero after a full refund succeeds.

Charges and refund records remain available for financial history and
audit purposes; voiding a charge does not delete it.

### Refund status messages

The appointment page may display one or more refund messages:

- **Refund pending** — the refund has been requested and is awaiting
  processing.
- **Refund processing** — the refund is being processed by Stripe.
- **Refund completed** — Stripe has confirmed the refund succeeded.
- **Refund failed** — the refund could not be completed and needs staff
  attention.

There may be more than one refund record for an appointment, such as
when a partial refund has already been made or an earlier refund attempt
failed. Read all status messages before taking further action.

### Automatic updates

While the staff appointment page is open, refund status messages and
the financial summary update automatically when the system receives
refund status changes. Staff normally do not need to refresh the page.

If the connection is interrupted or the page has been closed, reopening
or refreshing the appointment will display the latest recorded state.

### When a refund fails

A red **Refund failed** message indicates **Staff attention required**.
Review the appointment's payment and refund history and follow the
practice's escalation procedure. Do not assume the patient has been
refunded, and do not initiate a second refund without checking the
existing payment and refund records.

The staff interface currently shows refund status, but it does not
provide a manual refund initiation or retry control. Failed refunds
are not automatically retried.

### Online booking payment exceptions

If Stripe collects payment but an online appointment cannot be created
(for example, because its hold expired), the payment can be marked
`requires_refund`. Payment and refund history is retained separately
from appointment records in this case.

## Stripe Booking Payment Reconciliation

**For Staff Admins and Senior Staff Admins.** Open **Booking payment reconciliation** from the practice navigation, or visit `/practice/booking_payment_reconciliations`. This is an administrative review queue for unresolved **online Stripe booking payments**, not a tool for taking a new payment or issuing a refund.

### When a payment appears

The queue shows Stripe payments associated with your practice that have been **pending** or **processing** for at least 15 minutes and do not yet have an appointment attached. A payment can remain here when the booking process did not receive a definitive result from Stripe. The queue is limited to the 100 oldest matching payments.

**Do not assume that an unresolved payment means the patient has not been charged.** Before starting any replacement booking or payment attempt, investigate the existing payment outcome. A Stripe timeout or unavailable verification is not grounds for creating an unpaid appointment.

### Finding and verifying a payment

1. Search by **patient name**, **guest name**, **payment reference** or **Stripe PaymentIntent ID**. The search is limited to payments for your practice.
2. Check the matching payment reference, patient or booking details and local payment status.
3. Review the PaymentIntent in the **correct Stripe account and mode** (live or test, as appropriate). Check the payment outcome and transaction details.
4. In the **Stripe PaymentIntent ID** field, confirm the correct `pi_...` reference and select **Verify payment with Stripe**.
5. Read the result and the **Stripe status (last checked)** column. Its timestamp refers to the **last audited verification**, not a continuously live Stripe status. Verify again if you need a fresh result.

Verification checks the PaymentIntent against the local payment and records an audit event. **It does not create a new charge.** A confirmed successful payment may be recovered and reconciled with its booking; otherwise the payment remains unresolved until the appropriate next action is clear. Search and verification results update on the page without a full reload.

### Cancelling an abandoned payment

Use **Cancel abandoned payment** only when the original payment attempt is genuinely abandoned and you have checked the PaymentIntent in Stripe. Cancellation prevents further payment attempts using that PaymentIntent and cannot be undone. **It does not refund a successful payment.**

1. Confirm the payment reference and PaymentIntent ID match the intended booking attempt.
2. Confirm in Stripe that the PaymentIntent has **not succeeded** and is eligible for cancellation.
3. Select **Cancel abandoned payment**.
4. Read the confirmation dialog carefully and verify the exact PaymentIntent ID before continuing.
5. Check the success message and the Stripe Dashboard. When cancellation is confirmed and the local outcome is reconciled, the payment disappears from the unresolved queue.

The application also checks Stripe status, metadata, amount and currency before permitting cancellation. If the check or cancellation cannot be confirmed, the payment remains available for investigation; do not assume it was cancelled.

### If Stripe is unavailable or the outcome is uncertain

- Leave the payment unresolved and escalate according to your practice's payment investigation procedure.
- **Do not repeat the charge**, create an emergency unpaid booking for the same existing payment attempt, or repeatedly press cancellation hoping for a different result.
- Check the original PaymentIntent, any associated charge, and the local audit history before taking further action.
- If a successful payment is discovered but no valid appointment can be created, use the established payment/refund investigation process rather than booking the appointment manually.
- For failed or uncertain **refunds**, follow [Payments and Refunds](#payments-and-refunds); this reconciliation queue is not a refund retry facility.

Only suitably authorised administrators can perform these actions, and reconciliation results are recorded for audit purposes.

## Clinician Availability

Clinician availability determines which appointment slots may be booked.
Only available slots can be selected during staff appointment booking.
Staff Clinicians can create, edit and cancel only their own availability.
Staff Admins and Senior Staff Admins can manage availability across the practice.
Basic Staff cannot manage availability.

## User and Staff Administration

### Patient records

![Simplified illustration of the practice patient list with a new patient button](images/user_manual/patients-list-illustration.png)

*Patients list: View patients registered with your practice, open an existing
patient record or begin a new registration.*

Staff can open **Patients** from the practice navigation to view patients
registered with their practice. Select **New patient** to register a patient,
entering a unique patient number, first name, last name and date of birth.
Select a patient from the list to view or edit their details. Patient records
from other practices are not available through these pages.

![Simplified illustration of the patient registration form](images/user_manual/new-patient-illustration.png)

*New patient: Enter the patient number, first name, last name and date of
birth, then save the new patient record.*

### Staff directory and access levels

![Simplified illustration of the staff directory with staff types and access levels](images/user_manual/staff-directory-illustration.png)

*Staff directory: View colleagues linked to your practice. Staff type describes
their responsibilities; access level determines their administrative permissions.*

The staff directory is currently available at `/practice/staff_members`.
It lists staff members associated with the signed-in user's practice.

A staff member's type (doctor, nurse or administrator) describes their
responsibilities. Their *access level* separately determines administrative
authority within that practice:

- **Staff** — the default level for every new staff membership; can view the
  appointment diary and staff directory, but cannot make operational changes.
- **Staff Clinician** — available to doctors and nurses; can manage appointments,
  patients and payments, but only their own availability. Additional access to
  medical records is planned but has not yet been enabled.
- **Staff Admin** — can manage operational work and ordinary staff accounts,
  but cannot change access levels or administer privileged staff accounts.
- **Senior Staff Admin** — has full operational access and can change access
  levels for staff in their own practice.

Only Senior Staff Admins may change another staff member's access level.
To do so, open **Staff**, select **Edit access** beside a colleague, choose
the appropriate level and select **Save access level**. Select **Cancel**
to leave their access unchanged. Staff Clinician is available only for
colleagues whose staff type is Doctor or Nurse.

The server rejects requests from ordinary Staff and Staff Admin accounts,
as well as requests affecting staff in a different practice. Senior Staff
Admins cannot demote themselves. A staff member's access level in one
practice does not confer those permissions in another.

### Adding a staff member

![Simplified illustration of the new staff member form](images/user_manual/new-staff-member-illustration.png)

*New staff member: Enter your colleague's email address and practice details,
then select Create staff member.*

Staff Admins and Senior Staff Admins can add colleagues to their practice.
Open the staff directory at `/practice/staff_members` and select
**New staff member**. Enter the colleague's email address, name, staff type
(doctor, nurse or administrator), and any applicable registration number. First name and last name are required.
The form highlights missing required fields. Then select **Create staff member**.

New colleagues always start with **Staff** access. A Senior Staff Admin must
approve any subsequent change to their access level.

If the email address is new to Ballyclare Medical, the system creates an
account and sends a **Welcome to Ballyclare Medical** email to that address.
The colleague selects **Set your password**, enters and confirms a new
password, and selects **Set my password**. After successful setup, the
application signs them in and redirects to the home page.
If an account already exists, it is linked to the practice without changing
the person's existing password or sending another password-setting email.

![Simplified illustration of the staff onboarding flow from account creation to sign-in](images/user_manual/staff-invitation-flow-illustration.png)

*Staff onboarding: An administrator adds a colleague, the new colleague
receives password-setting instructions, chooses a password and signs in.
Existing account holders continue using their current password.*

If an error appears, correct the details and try again. An existing staff
member cannot be added to the same practice twice.

**Invitation links:** Password setup links expire and cannot be reused after
successful password setup. If a link has expired, use the **Forgot password?**
option on the sign-in page or contact your practice administrator for help.

**Email availability:** Sending invitations requires the platform operator
to configure the application's outgoing email service. If an expected
message does not arrive, ask the platform operator to check email delivery;
do not share passwords or create a duplicate account.

### Editing staff details

From the staff directory, select **Edit details** beside a colleague to
change their first name, last name, registration number or staff type.
The email address is displayed for reference but cannot be edited here.
First and last names are required. Select **Save changes** to apply updates,
or **Cancel** to return without saving. Access levels are managed separately
through **Edit access** by a Senior Staff Admin.

### Deactivating and reactivating staff

Authorised administrators can select **Deactivate** beside an active staff
member in the staff directory and confirm the action. The colleague remains
listed with an **Inactive** badge and a **Reactivate** action. Deactivation
blocks their access to protected practice pages without deleting their
staff record or appointment history.

If an inactive staff member tries to sign in with their correct email and
password, the sign-in page displays **Your staff account is inactive** and
asks them to contact their practice administrator. Incorrect credentials
still receive the normal sign-in error; account status is not disclosed
before password verification.

If a staff member was already signed in when deactivated, opening a
protected practice page displays an account-inactive message with a
**Sign out** button rather than a blank page. Select **Sign out** to end
the session. An administrator can select **Reactivate** in the staff
directory to restore practice access. Reactivation does not require a
new invitation or password.

### Setting up the first Senior Staff Admin

When a new practice is added, an authorised platform operator sets up its
first Senior Staff Admin. The practice should provide the intended
administrator's email address and confirm who is authorised to manage
staff access.

The initial setup is not yet available through the staff interface.
Contact the platform operator to arrange it; practice staff do not need
to use a terminal or Rails console. Once setup is complete, the
administrator can sign in using their own account.

A practice can only go through this initial setup before any staff
members have been registered. If the practice already has staff, contact
the platform operator rather than trying to repeat the setup.

The initial Senior Staff Admin setup is a separate operator process; the
ordinary staff invitation form cannot grant senior permissions.
Never share passwords or use a shared administrator login.

### Recovering administrative access

If a practice has existing staff but no accessible Senior Staff Admin,
**do not rerun bootstrap or create a substitute privileged account using
seed data**. Escalate to an authorised platform operator to verify the
practice and account ownership before recovery. A dedicated, audited
recovery workflow has not yet been implemented.

Do not deactivate the last active Senior Staff Admin. If senior access is
lost, contact an authorised platform operator for recovery.

## Troubleshooting

**Cannot find a patient when booking:** Search by first name, surname or
patient number. Only the first five matching results appear; type more of
the name or number to narrow the list. If the patient has not yet been
registered with your practice, an authorised staff member can add them
through **Patients → New patient**.

**Appointment time disappears or cannot be booked:** Another booking or
temporary hold may have taken the slot. Choose another available time.
Do not repeatedly submit the same appointment if a confirmation has
already appeared; check the diary first.

**Cannot sign in after deactivation:** If the account-inactive message
appears after entering the correct password, contact your practice
administrator. Resetting the password does not reactivate staff access.

**Invitation email not received:** Check your inbox and junk folder. If
email delivery is not configured, contact the platform operator.

**Password setup link expired:** Use **Forgot password?** from the sign-in
page to request a new password link.


If an appointment's refund does not update immediately, check the
current refund status and allow time for Stripe processing. Refresh the
appointment page if the live connection has been interrupted.

For a failed refund, follow the escalation guidance above rather than
repeatedly attempting payment or cancellation actions.
