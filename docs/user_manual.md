# Ballyclare Medical User Manual

This guide is intended for nontechnical users of the Ballyclare Medical
system, including reception, administrative and clinical staff.

The manual is being developed alongside the application. Sections will be
expanded as the corresponding features become available.

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

Ballyclare Medical is a practice management system designed to support
day-to-day medical practice operations.

The system will provide facilities for managing patients, clinician
availability, appointments, payments and clinical encounters.

## Payments and Refunds

The system supports payment processing as part of the appointment booking
process.

When a patient selects an appointment, the appointment slot may be held
temporarily while payment is being completed.

Further instructions for taking payments, viewing payment status and
processing refunds will be added as these features become available.

## Appointment payments

When payment is required for an appointment, the system records the payment against the patient and appointment.

A successful payment completes the appointment booking automatically.

If payment succeeds but the appointment cannot be completed, the payment is flagged for refund so that staff can identify and resolve it.

Payment and refund records are retained as part of the financial history and are not removed when related clinical or scheduling records change.

## Payments and Refunds

The system supports payment processing as part of the appointment booking process.

When a patient selects an appointment, the appointment slot is held temporarily while payment is being completed. This prevents another patient from booking the same slot during the payment process.

When payment succeeds and the appointment slot is still available, the system completes the appointment booking automatically.

If payment succeeds but the appointment can no longer be completed, for example because the appointment hold has expired, the payment is marked as requiring a refund. No appointment is created in this situation.

Refunds are recorded separately from the original payment so that the financial history remains clear. The system tracks the refund while it is being processed and records when the payment provider confirms that the refund has succeeded.

Expired appointment holds are retained when they form part of the payment history. An expired hold does not permanently block the appointment slot, and the slot can be offered to another patient when it is otherwise available.

Payment and refund records are retained as part of the financial history and are not removed when related scheduling records change.

### Current refund workflow

At the current stage of development, the system records and tracks refunds through the payment provider, but a staff-facing screen for initiating and managing refunds has not yet been added.

A payment that succeeds when its appointment cannot be completed is marked as `requires_refund`.

A refund record can then be created for that payment. Once the payment provider confirms that the refund has succeeded, the refund is recorded as successful together with the date and time of confirmation.

The original payment and its refund remain linked so that the complete financial history can be reviewed.

Further staff instructions will be added when the payment and refund administration screens become available.
