# Ballyclare Medical User Manual

This guide is intended for reception, administrative and clinical staff using
Ballyclare Medical. It is being expanded as new features become available.

## Contents

1. Getting Started
2. Signing In
3. Patients
4. Appointment Diary
5. Booking an Appointment
6. Cancelling an Appointment
7. Payments and Refunds
8. Clinician Availability
9. User and Staff Administration
10. Troubleshooting

## Getting Started

Ballyclare Medical supports day-to-day practice operations, including patients,
clinician availability, appointments and payments. Some clinical and
administrative features are still under development.

## Appointment Diary

The staff appointment diary lets staff view appointments and open an
appointment to review its status, financial summary and activity history.

## Booking an Appointment

Staff can book an available appointment for a patient, choose the clinician
and appointment slot, and enter a consultation charge. The appointment page
shows the recorded charge and any payments received.

For online bookings requiring payment, an appointment slot may be held
temporarily while payment is completed. An expired hold does not permanently
block the slot from being offered again.

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

## Clinician Availability

Clinician availability determines which appointment slots may be booked.
Only available slots can be selected during staff appointment booking.

## User and Staff Administration

### Patient records

Staff can open **Patients** from the practice navigation to view patients
registered with their practice. Select **New patient** to register a patient,
entering a unique patient number, first name, last name and date of birth.
Select a patient from the list to view or edit their details. Patient records
from other practices are not available through these pages.

### Staff directory and access levels

The staff directory is currently available at `/practice/staff_members`.
It lists staff members associated with the signed-in user's practice.

A staff member's type (doctor, nurse or administrator) describes their
responsibilities. Their *access level* separately determines administrative
authority within that practice:

- **Staff** (`staff`) — the default level for every new staff membership.
- **Staff Admin** (`staff_admin`) — intended to manage ordinary staff
  accounts once staff creation is available.
- **Senior Staff Admin** (`senior_staff_admin`) — can change access levels
  for staff in their own practice.

Only Senior Staff Admins may change another staff member's access level.
The server rejects requests from ordinary Staff and Staff Admin accounts,
as well as requests affecting staff in a different practice. Senior Staff
Admins cannot demote themselves. A staff member's access level in one
practice does not confer those permissions in another.

**Current limitation:** Staff account creation, invitations and access-level
editing controls are not yet available through the user interface. A
permission-protected access-level update endpoint exists, but is not exposed
in the staff directory.

### Provisioning the first Senior Staff Admin

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
does **not** create a user or send an invitation. Secure staff invitation
and password setup are planned separately. Avoid putting real patient or
staff credentials in application logs or documentation.

### Recovering administrative access

If a practice has existing staff but no accessible Senior Staff Admin,
**do not rerun bootstrap or create a substitute privileged account using
seed data**. Escalate to an authorised platform operator to verify the
practice and account ownership before recovery. A dedicated, audited
recovery workflow has not yet been implemented.

Protection against losing the last active Senior Staff Admin during
deactivation or removal is also planned before those actions are available.

## Troubleshooting

If an appointment's refund does not update immediately, check the
current refund status and allow time for Stripe processing. Refresh the
appointment page if the live connection has been interrupted.

For a failed refund, follow the escalation guidance above rather than
repeatedly attempting payment or cancellation actions.
