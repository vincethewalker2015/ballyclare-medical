# Ballyclare Medical --- Product Roadmap

> **Status:** Living document\
> **Purpose:** Product, architecture, design, and delivery roadmap for
> the Ballyclare Medical platform.\
> **Principle:** Build reliable healthcare workflows first, then add
> intelligent capabilities on top of trusted data and clearly defined
> domain services.

------------------------------------------------------------------------

## 1. Product Vision

Ballyclare Medical is a modern medical-centre platform for patients,
clinicians, nurses, administrators, and practice staff.

The platform should provide a coherent experience across:

-   appointment availability and scheduling;
-   patient self-booking;
-   staff-assisted booking;
-   payments, balances, charges, and refunds;
-   patient records and clinical encounters;
-   clinical notes and follow-up workflows;
-   patient self-service;
-   practice administration;
-   trusted medical information;
-   intelligent search and AI-assisted experiences.

The system is designed as a **global platform**. Country-specific
assumptions must not be embedded into the domain model. Practices
configure their own timezone, currency, country, addresses, services,
and operational settings.

The product should remain useful without AI. AI is an enhancement layer
built on top of reliable application services, trusted content, explicit
permissions, and auditable workflows.

------------------------------------------------------------------------

## 2. Core Architecture Principles

### One application, distinct experiences

The patient and staff experiences belong to the same Rails application
but should be clearly separated.

``` text
/portal/...    Patient-facing experience
/practice/...  Staff and clinician experience
```

This allows both experiences to share the same domain model, security
model, scheduling engine, billing system, and clinical records without
becoming separate applications.

### Domain services own important operations

Controllers and views should remain thin. Important business operations
belong in explicit services.

Examples include:

``` text
Booking::CreateStaffAppointment
Billing::CreateCharge
Billing::AppointmentBalance
Payments::CreateForAppointment
Payments::TakeAppointmentPayment
Payments::HandleSucceeded
Payments::HandleFailed
Payments::CreateRefund
```

External providers should sit behind application-owned boundaries rather
than being scattered through controllers or models.

### PostgreSQL is the source of truth

Booking availability and financial state must not depend on what the
browser currently displays.

Database constraints, transactions, and row locking protect operations
such as:

-   acquiring an appointment slot;
-   creating holds;
-   booking appointments;
-   taking payments;
-   creating refunds;
-   calculating balances.

Turbo can provide a responsive interface, but the database remains
authoritative.

### Appointment state and financial state are independent

An appointment can be valid while money remains outstanding.

For example:

``` text
Appointment: completed
Balance:      75.00 outstanding
```

An unpaid appointment is not an invalid appointment.

### Charges and payments represent different concepts

`AppointmentCharge` records **what the patient owes**.

`Payment` records **money movement**.

`Refund` records **money returned**.

The appointment balance is derived from those records rather than stored
as an independent mutable value.

Conceptually:

``` text
active charges
- succeeded payments
+ succeeded refunds
= outstanding balance
```

This supports consultation fees, additional treatments, partial
payments, later payments, refunds, and overpayments.

### Global by design

Avoid assumptions such as:

-   GBP as the default currency;
-   UK-only patient identifiers;
-   UK-only address formats;
-   a single timezone;
-   fixed consultation prices.

Practices should configure these values explicitly.

------------------------------------------------------------------------

## 3. Design Direction

The visual direction should take inspiration from the qualities of the
STAT Wellness website while developing an original Ballyclare Medical
design system rather than copying its interface.

Reference:

https://www.statwellness.com

### Desired characteristics

The application should feel:

-   calm;
-   modern;
-   premium but approachable;
-   medically professional;
-   spacious;
-   easy to understand;
-   trustworthy;
-   consistent across public, patient, and staff interfaces.

The design should favour:

-   generous whitespace;
-   strong typography;
-   restrained colour;
-   clear visual hierarchy;
-   high-quality healthcare imagery where appropriate;
-   large, obvious primary actions;
-   simple cards and panels;
-   uncluttered forms;
-   clear status indicators;
-   excellent mobile behaviour.

### Three related interfaces

The platform will eventually have three visually related but
functionally distinct surfaces.

#### Public website

Marketing, practice information, services, medical information, and
entry points into booking and the patient portal.

The public site can carry more of the expressive visual character:
photography, editorial layouts, larger typography, and service
discovery.

#### Patient portal

Simple, reassuring, and task-oriented.

Primary patient tasks should include:

-   book an appointment;
-   see upcoming appointments;
-   manage payments;
-   review balances;
-   access approved documents and information;
-   update personal details;
-   receive communications.

#### Practice workspace

The staff interface should prioritise information density and speed over
marketing presentation while retaining the same design language.

Primary staff tasks include:

-   today's appointments;
-   booking;
-   patient search;
-   appointment management;
-   clinical workflow;
-   charges and payments;
-   refunds;
-   availability;
-   administration.

### Accessibility

Accessibility is a product requirement rather than a final polish step.

Design and implementation should consider:

-   WCAG 2.2 AA as the target;
-   keyboard navigation;
-   visible focus states;
-   semantic HTML;
-   sufficient colour contrast;
-   form labels and useful validation;
-   screen-reader friendly status changes;
-   reduced-motion preferences;
-   touch-friendly controls;
-   layouts that remain usable when text is enlarged.

------------------------------------------------------------------------

# Delivery Roadmap

## Phase 1 --- Platform Foundation

**Status: Completed**

The initial application and core domain foundation are in place.

Delivered:

-   Rails 8 application foundation;
-   PostgreSQL;
-   UUID primary keys;
-   authentication;
-   users and roles;
-   practices;
-   patients;
-   staff members;
-   global practice configuration concepts;
-   RSpec test infrastructure;
-   application service pattern;
-   initial domain relationships and constraints.

### Outcome

A stable domain foundation on which scheduling, finance, clinical
workflows, and portals can be built.

------------------------------------------------------------------------

## Phase 2 --- Scheduling and Booking Foundation

**Status: Completed**

Delivered:

-   availability blocks;
-   appointment slots;
-   appointment holds;
-   hold expiration;
-   historical hold preservation;
-   concurrency protection;
-   row locking;
-   patient/practice validation;
-   appointment creation;
-   appointment status foundation;
-   patient payment-before-booking workflow;
-   staff booking without mandatory upfront payment.

### Important rule

A slot may only be booked once.

The server and database enforce availability. The UI must never be
trusted to prevent double booking.

------------------------------------------------------------------------

## Phase 3 --- Billing, Payments, and Refund Foundation

**Status: Completed**

Delivered:

-   Stripe integration;
-   PaymentIntent creation;
-   idempotency keys;
-   payment webhooks;
-   successful payment handling;
-   failed payment handling;
-   appointment-linked payments;
-   hold-linked payments;
-   refunds;
-   partial refund support;
-   appointment charges;
-   additional-charge foundation;
-   appointment balance calculation;
-   partial appointment payments;
-   staff booking with an outstanding balance;
-   staff booking followed by optional payment.

### Payment workflow principle

Staff booking and payment are deliberately separate operations.

``` text
Create appointment
      ↓
Create appointment charge
      ↓
Appointment exists
      ↓
Optional payment now
      OR
Outstanding balance remains
```

A payment failure must not remove an otherwise valid staff-created
appointment.

### Payment robustness still to revisit

Before production, provider transport failures and reconciliation should
receive additional attention.

A network error while creating a Stripe PaymentIntent can be ambiguous:
the provider may have received the request even if the application did
not receive the response.

The long-term design should preserve idempotency and allow safe
reconciliation/retry rather than assuming every transport failure means
no provider-side payment exists.

------------------------------------------------------------------------

## Phase 4 --- Staff Practice Interface

**Status: Next**

Build the first complete user-facing vertical slice on top of the
existing backend.

### Initial practice workspace

Create the `/practice` namespace and shared staff layout.

Initial navigation should include:

-   Dashboard;
-   Appointments;
-   Patients;
-   Payments;
-   Clinical;
-   Administration.

### Staff appointment diary

Provide:

-   today's appointments;
-   upcoming appointments;
-   clinician filtering;
-   status;
-   patient;
-   appointment time;
-   outstanding balance indication;
-   quick actions.

### Staff-assisted booking

Staff should be able to:

1.  find or select a patient;
2.  select a clinician;
3.  see genuine available slots;
4.  select a slot;
5.  enter the reason for appointment;
6.  enter/select the appropriate consultation charge;
7.  create the appointment;
8.  optionally take payment immediately;
9.  leave the balance outstanding when payment is not taken.

The appointment must be committed before optional payment processing
begins.

### Appointment view

Provide a single staff appointment screen showing:

-   appointment details;
-   patient;
-   clinician;
-   status;
-   charges;
-   payments;
-   refunds;
-   current balance;
-   relevant history;
-   available actions.

------------------------------------------------------------------------

## Phase 5 --- Patient Portal

**Status: Planned**

Create the `/portal` experience.

### Patient dashboard

Patients should see:

-   next appointment;
-   upcoming appointments;
-   outstanding balances;
-   useful actions;
-   recent communications.

### Self-booking

Patient booking should follow the established hold-based flow:

``` text
Choose appointment
       ↓
Acquire temporary slot hold
       ↓
Confirm details and charge
       ↓
Payment
       ↓
Stripe confirmation
       ↓
Create appointment
```

The UI should clearly communicate temporary holds and payment progress.

### Patient appointment management

Planned capabilities include:

-   upcoming appointments;
-   appointment history;
-   cancellation where permitted;
-   rescheduling where permitted;
-   payment history;
-   outstanding balances;
-   later payment;
-   approved documents;
-   personal details.

------------------------------------------------------------------------

## Phase 6 --- Appointment Lifecycle and Clinical Workflow

**Status: Planned**

Formalise operational appointment transitions.

Example lifecycle:

``` text
booked
  ↓
confirmed
  ↓
arrived
  ↓
in_consultation
  ↓
completed
```

Alternative outcomes include:

``` text
cancelled
referred
did_not_attend
```

### Status history

Every meaningful appointment transition should be recorded through
`AppointmentStatusChange`.

Where appropriate, capture:

-   previous status;
-   new status;
-   timestamp;
-   responsible user;
-   reason/context.

### Encounters

An `Encounter` represents the clinical event rather than the scheduling
event.

The encounter workflow should support:

-   consultation start;
-   clinician;
-   clinical information;
-   completion;
-   history.

### Clinical notes

Clinical notes require stricter access and audit behaviour than ordinary
administrative information.

Future work should include:

-   authorisation;
-   author attribution;
-   timestamps;
-   appropriate amendment behaviour;
-   audit trail;
-   safe presentation to patients where applicable.

------------------------------------------------------------------------

## Phase 7 --- Charges, Services, and Practice Fee Catalogue

**Status: Planned**

The existing `AppointmentCharge` remains the historical financial
record.

Introduce a practice-configurable service/fee catalogue to make routine
charging easier.

Possible concepts:

``` text
Service
  practice
  name
  description
  suggested/default amount
  currency
  active
```

A catalogue item may suggest the normal price, but an appointment charge
should snapshot the actual description, amount, and currency used at the
time.

This prevents later catalogue changes from rewriting financial history.

### Additional charges

Authorised staff should be able to add appropriate charges during or
after an appointment.

Examples could include practice-defined treatments, procedures, tests,
or services.

The platform must not assume fixed universal prices.

------------------------------------------------------------------------

## Phase 8 --- Medical Knowledge Base

**Status: Planned**

This is the foundation for medical-information discovery and later AI
functionality.

### Core principle

> **Medical Knowledge Base → Intelligent Search/Retrieval → AI
> Assistant**

AI should not be the original source of medical facts presented by the
platform.

The platform should first establish a trusted, structured, attributable
medical knowledge base.

### Diseases and conditions directory

Provide a public/patient-facing feature similar in concept to
established medical A--Z directories:

``` text
Diseases & Conditions

[A] [B] [C] [D] ... [Z]
```

Users should be able to:

-   browse by first letter;
-   search by condition name;
-   find common aliases/synonyms;
-   open a condition page;
-   navigate related trusted information.

This is primarily a **structured content and search feature**, not an AI
feature.

### Possible condition structure

Conceptually:

``` text
MedicalCondition
  name
  slug
  summary
  symptoms
  causes
  risk_factors
  diagnosis
  treatment
  when_to_seek_help
  source
  source_url
  reviewed_at
  published_at
```

Additional models may support:

-   aliases;
-   categories;
-   related conditions;
-   references;
-   content revisions.

The exact schema should be designed when this phase begins.

### Content provenance

Medical information must have identifiable provenance.

Where applicable, retain:

-   source organisation;
-   source URL/reference;
-   publication/review date;
-   internal review status;
-   content revision history.

We should not populate the knowledge base by simply asking an LLM to
generate diseases and medical advice.

------------------------------------------------------------------------

## Phase 9 --- Intelligent Medical Search and Retrieval

**Status: Planned**

Once the knowledge base exists, introduce intelligent retrieval.

Traditional search remains available.

Intelligent retrieval adds the ability to understand natural-language
questions and retrieve relevant trusted material.

Example:

``` text
Patient:
"I've had a dry cough at night and sometimes feel wheezy."

          ↓

Interpret search intent

          ↓

Retrieve relevant material from the
approved Medical Knowledge Base

          ↓

Present relevant conditions/topics
and source material
```

The system should distinguish between:

-   finding relevant information;
-   explaining information;
-   diagnosing a patient.

These are not equivalent operations.

The search layer should not silently turn information retrieval into an
autonomous diagnosis.

------------------------------------------------------------------------

## Phase 10 --- AI Assistant

**Status: Planned / Later**

AI is introduced **after** the trusted knowledge and retrieval layers.

Architecture:

``` text
                  ┌──────────────────────────┐
                  │ Medical Knowledge Base   │
                  │ trusted + attributable   │
                  └────────────┬─────────────┘
                               │
                               ▼
                  ┌──────────────────────────┐
                  │ Intelligent Retrieval    │
                  │ search / relevance       │
                  └────────────┬─────────────┘
                               │
                               ▼
                  ┌──────────────────────────┐
                  │ AI Assistant             │
                  │ explanation + dialogue   │
                  └──────────────────────────┘
```

### AI principle

> AI assists users in finding, understanding, summarising, and working
> with trusted information. It does not replace the underlying medical
> knowledge base or autonomously make consequential clinical decisions.

### Initial AI use cases

Potential early uses include:

#### Medical information assistant

Allow a patient to ask a natural-language question.

The assistant retrieves approved medical information and explains it in
accessible language while providing links/references to the underlying
material.

#### Clinician information retrieval

Allow clinicians to locate relevant internal/approved medical material
quickly without replacing their clinical judgement.

#### Consultation summarisation

AI may eventually propose a structured summary from clinician-authored
consultation information.

The clinician should review and approve material before it becomes an
authoritative clinical record.

#### Patient-friendly explanations

AI could help transform approved clinical or educational information
into clearer language, subject to appropriate safeguards.

### AI must not directly control consequential domain actions

An AI response must not silently:

-   diagnose a patient;
-   prescribe medication;
-   alter a clinical record;
-   add or remove a charge;
-   refund money;
-   book/cancel an appointment;
-   change appointment status;
-   change patient identity information.

If an AI-assisted workflow eventually proposes one of these actions, it
should go through an explicit application service, permission check,
validation, and --- where appropriate --- human confirmation.

### Provider abstraction

AI providers should sit behind an application-owned interface.

Conceptually:

``` text
Rails application
       │
       ▼
   AI service layer
       │
       ├── hosted AI provider
       ├── alternative provider
       └── future private/local model
```

The application should not become tightly coupled to one model vendor.

Possible structure:

``` text
app/services/ai/
  client.rb
  condition_search.rb
  medical_content_answer.rb
  consultation_summary.rb
```

The exact provider and implementation should be selected when the AI
phase begins.

### Asynchronous AI work

Long-running AI tasks should normally run outside the web request where
appropriate.

Rails Active Job and the application's queue infrastructure can support:

-   summarisation;
-   indexing;
-   embedding generation;
-   document processing;
-   non-interactive analysis.

Interactive assistant requests may require streaming or other
request-specific handling.

### AI auditability

Where AI interacts with healthcare information, we should be able to
establish appropriate records of:

-   what feature invoked AI;
-   which provider/model configuration was used where relevant;
-   which trusted sources were retrieved;
-   whether output was accepted/edited by a clinician where applicable;
-   when the operation occurred.

The precise audit policy will depend on the use case and applicable
regulatory/privacy requirements.

------------------------------------------------------------------------

## Phase 11 --- Communications and Notifications

**Status: Planned**

Introduce a provider-neutral communication layer.

Potential capabilities:

-   appointment confirmation;
-   reminders;
-   cancellation notices;
-   payment receipts;
-   payment reminders;
-   refund confirmation;
-   practice messages.

Potential channels:

-   email;
-   SMS;
-   in-app notifications.

Communications should be generated from domain events/workflows rather
than tightly coupling external messaging providers to core models.

------------------------------------------------------------------------

## Phase 12 --- Practice Administration and Reporting

**Status: Planned**

Provide administrative tooling for:

-   staff;
-   roles and permissions;
-   clinicians;
-   availability;
-   practice settings;
-   services and fees;
-   payment/refund visibility;
-   appointment reporting;
-   financial reporting;
-   operational reporting.

Reports should respect practice boundaries and authorisation.

------------------------------------------------------------------------

## Phase 13 --- Security, Privacy, Compliance, and Production Readiness

**Status: Continuous, with dedicated production phase**

Healthcare software requires security and privacy work throughout
development rather than at the end.

Before production deployment, perform a dedicated review covering at
least:

-   authentication;
-   authorisation;
-   practice isolation;
-   patient access boundaries;
-   clinical-data access;
-   audit logging;
-   secret management;
-   encryption;
-   backups and restore testing;
-   retention policies;
-   error reporting;
-   monitoring;
-   dependency/security scanning;
-   webhook security;
-   payment handling;
-   AI data handling;
-   data sent to external providers;
-   consent where required;
-   applicable healthcare/privacy regulation for deployment
    jurisdictions.

Regulatory requirements must be evaluated for the actual countries and
healthcare contexts in which the platform is deployed.

------------------------------------------------------------------------

# Cross-Cutting Workstreams

## Authorisation

Role names alone should not become the entire security model.

Authorisation should answer whether the current user may perform a
specific operation against a specific resource.

Examples:

-   Can this staff member see this patient?
-   Can this user add a clinical note?
-   Can this user add or void a charge?
-   Can this user request a refund?
-   Can this patient see this document?

Practice isolation must be enforced server-side.

------------------------------------------------------------------------

## Audit Trail

Important actions should produce appropriate audit records.

Candidates include:

-   appointment creation;
-   appointment status changes;
-   cancellations;
-   patient-detail changes;
-   clinical-record activity;
-   charges;
-   charge voiding;
-   payments;
-   refunds;
-   permission/role changes;
-   AI-assisted clinical workflows where appropriate.

Audit records should describe what occurred without becoming a mechanism
for unnecessarily duplicating sensitive clinical content.

------------------------------------------------------------------------

## Testing Strategy

Maintain the current backend-first testing discipline.

Use:

-   model specs for invariants and relationships;
-   service specs for business workflows;
-   request specs for controller/API behaviour;
-   system specs for critical end-to-end user journeys;
-   concurrency tests where race conditions matter;
-   provider adapters mocked at unit/service boundaries;
-   selective real sandbox verification for external payment behaviour.

Critical booking and financial rules should remain protected
independently of the UI.

------------------------------------------------------------------------

## Performance

Optimise based on observed behaviour rather than premature assumptions.

Likely future areas include:

-   appointment availability queries;
-   diary/calendar queries;
-   patient search;
-   medical knowledge search;
-   AI retrieval/indexing;
-   reporting.

Database indexes and query plans should be reviewed as real usage
patterns emerge.

------------------------------------------------------------------------

# Recommended Delivery Order

The current recommended sequence is:

``` text
1. Staff Practice UI
        ↓
2. Staff booking vertical slice
        ↓
3. Appointment management + lifecycle
        ↓
4. Patient Portal
        ↓
5. Patient self-booking UI
        ↓
6. Clinical encounter workflow
        ↓
7. Charges / service catalogue
        ↓
8. Communications
        ↓
9. Medical Knowledge Base
        ↓
10. Intelligent Search / Retrieval
        ↓
11. AI Assistant
        ↓
12. Reporting / expanded administration
        ↓
13. Production hardening and jurisdiction-specific compliance
```

This order is intentionally flexible. New requirements may move
individual phases, but architectural dependencies should be respected.

In particular:

``` text
Medical Knowledge Base
        ↓
Intelligent Search / Retrieval
        ↓
AI Assistant
```

should remain the preferred order for patient-facing medical
information.

------------------------------------------------------------------------

# Near-Term Development Plan

The next implementation branch should begin the **staff practice
interface**.

Suggested first vertical slice:

``` text
/practice/appointments
        ↓
Staff appointment diary
        ↓
"Book appointment"
        ↓
Patient selection
        ↓
Available slot selection
        ↓
Appointment + initial charge
        ↓
Appointment created
        ↓
Optional "Take payment now"
        ↓
Appointment detail / balance
```

This deliberately exercises the backend services already built before
expanding into additional backend abstractions.

Any missing backend operation discovered while implementing this slice
should be added behind a tested domain service rather than implemented
directly in the controller.

------------------------------------------------------------------------

# Decisions to Preserve

These decisions should not be casually changed without revisiting the
architectural reasoning.

1.  **Patient and User are separate concepts.**\
    A patient can exist without having a portal login.

2.  **StaffMember and User are separate concepts.**\
    Authentication identity and practice staff information have
    different responsibilities.

3.  **Appointment and Encounter are separate.**\
    Scheduling and clinical care are related but distinct domains.

4.  **Appointment status and payment status are separate.**

5.  **Charges represent debt; payments represent money movement.**

6.  **Staff-created appointments do not require payment at booking
    time.**

7.  **Staff may optionally take payment immediately after creating an
    appointment.**

8.  **Patients may pay outstanding balances later, including after an
    appointment.**

9.  **Additional charges are variable and practice-defined.**

10. **Expired appointment holds may be retained for financial/history
    purposes.**

11. **Booking concurrency is enforced server-side with PostgreSQL
    locking/constraints.**

12. **The application is global; UK-specific values are examples, not
    platform defaults.**

13. **Patient and staff experiences remain in one Rails application with
    separate namespaces.**

14. **AI augments trusted application data and workflows; it does not
    become the source of truth.**

15. **Medical information follows the architecture:**

    ``` text
    Medical Knowledge Base → Intelligent Search/Retrieval → AI Assistant
    ```

------------------------------------------------------------------------

# Definition of Done for Major Features

A major feature is not complete simply because its UI works.

Where applicable, completion includes:

-   domain behaviour;
-   database constraints;
-   authorisation;
-   service-level tests;
-   request/system tests;
-   useful error states;
-   audit behaviour;
-   responsive UI;
-   accessibility;
-   documentation;
-   security considerations;
-   external-provider failure handling.

------------------------------------------------------------------------

# Living Roadmap

This document should evolve with the product.

When a significant feature is merged:

1.  update its phase/status here;
2.  record important architectural decisions;
3.  move newly discovered work into the appropriate future phase;
4.  avoid turning the roadmap into a detailed issue tracker.

GitHub issues/PRs should contain implementation-level work.

This roadmap should remain the higher-level reference for **what we are
building, in what order, and why**.
