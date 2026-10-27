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

**Status: Substantially implemented — refinement and verification ongoing**

The `/practice` workspace and the first staff booking vertical slice are now
implemented. The original requirements below are retained as a reference;
remaining work concerns fee configuration, fuller clinical workflows,
accessibility/system-test coverage, and continued production hardening.

**Verified delivery:** appointment diary (board/list and date filters), staff
booking, searchable practice-scoped patient picker (maximum five results),
clinician/slot selection, appointment details and lifecycle actions, charges,
balances, and optional payment. The patient picker and Solid Cache migration
were tested locally and deployed successfully to Render in October 2026.

**Not yet complete:** staff-managed consultation-fee defaults and any remaining
practice-dashboard/clinical navigation or end-to-end coverage gaps should be
reviewed rather than presumed delivered.

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

**Status: In progress — registration, portal foundation and paid booking implemented; completion audit outstanding**

The current implementation uses `PatientAccount` authentication and
`/patient-portal` routes (rather than the earlier proposed `/portal`
namespace). Registration creates a practice-scoped request requiring staff
verification/approval; patient dashboard, appointment discovery, holds and
payment routes exist. Public `/book` guest booking is also delivered, but
it is a separate anonymous workflow and does **not** complete Phase 5.

**Remaining acceptance work to verify/implement:**

- End-to-end account activation, email verification, staff approval and secure
  linking to existing patient records, including abuse and enumeration tests.
- Portal appointment history, cancellation and rescheduling policies, with
  appropriate audit and financial/refund behaviour.
- Payment history, receipts, outstanding balances and later payments within
  the authenticated portal.
- Approved documents, personal-detail management and patient communications
  where required for the agreed Phase 5 scope.
- End-to-end request/system, accessibility, practice-isolation and permission
  regression tests, plus production email delivery verification.

Existing routes and controllers establish implementation progress, **not**
proof that every workflow or acceptance criterion is complete.

### Patient registration and secure record linking

- Patients can create a login, verify their email and complete a patient
  profile appropriate to the configured practice/country.
- Preserve separate `User` and `Patient` concepts: patients may exist
  without logins, and user accounts must not silently create duplicate records.
- Resolve which practice a new patient is registering with; avoid assuming a
  single practice or using an arbitrary staff-associated practice.
- Existing patient records require a secure, auditable account-linking process.
  Matching names, birthdays or email addresses alone must **not** authorise
  access to an existing medical record. Provide staff-assisted exception handling.
- Confirm verification, privacy, anti-enumeration and abuse protections before
  enabling public registration in a live healthcare setting.

### Shared booking architecture (DRY)

Staff and patient booking share **domain rules and services** for availability,
slot validity, practice membership, concurrency control and authoritative fee
resolution. They do not need identical controllers or identical transaction
ordering. Extract common invariants carefully from the existing
`Booking::CreateStaffAppointment`, `Booking::CreateAppointment` and
`Payments::CompleteBooking` services while preserving their existing locking,
idempotency and webhook/reconciliation guarantees.

- **Staff route:** select patient and slot, resolve/show consultation fee,
  create appointment plus charge, then optionally take payment or leave an
  outstanding balance. Authorised staff may follow an explicit adjustment
  policy; an amount from the browser is never trusted unconditionally.
- **Patient route:** select consultation type/clinician and slot, resolve fee
  server-side, acquire a temporary hold, take mandatory online payment, then
  confirm/create the appointment only after verified payment success.
- Patient self-booking does **not** expose an unpaid-booking option. Failed or
  ambiguous payment outcomes must be reconciled safely and must not produce
  duplicate bookings or leave unhandled financial transactions.
- Both experiences rely on a shared source of truth for consultation fees;
  neither hardcodes the price into JavaScript, controllers or payment forms.

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

**Status: Partially implemented**

Appointment transitions and status history have a staff-facing foundation.
`Encounter` and `ClinicalNote` models also exist, but clinical consultation
routes, documentation workflows, stricter clinical permissions and amendment/
audit review remain future work. Do not equate existing models with a completed
clinical-record feature.

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

**Status: Planned — initial consultation-fee configuration pulled forward**

**Confirmed product decision (October 2026):** configure fees **per clinician
type**, not per individual clinician. The initial Ballyclare Medical settings
are **£65.00 for a doctor consultation** and **£40.00 for a nurse consultation**.
These are *editable starting values*, not global platform defaults or constants.
Only authorised practice staff may change them. Per-clinician overrides are out
of scope for the initial implementation.

Implement the consultation-fee settings **before** patient self-booking:

- Store prices per practice and clinician type as integer minor currency units,
  associated with the practice's configured currency.
- Use a single server-side price resolution service for both staff and patient
  flows; validate an active clinician's type and practice membership.
- Show the current fee before patient payment and revalidate it at checkout;
  define an explicit policy for price changes during a temporary hold.
- Snapshot the amount, currency and meaningful description in the booking's
  financial records so later fee edits never rewrite historical charges.
- Enforce staff-only permissions, input validation, change auditing and tests
  for the settings and pricing behaviour.

The broader service catalogue and optional additional-charge catalogue remain
planned for a subsequent part of Phase 7.

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

## Phase 10 --- Ballyclare Public AI Health & Booking Assistant

**Status: Planned — public Ballyclare-only initial release**

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

# AI Integration Strategy & Architecture

**Decision status:** Direction agreed; implementation deferred until the
medical knowledge and retrieval foundations are ready. **Initial product:**
Ballyclare Medical public AI Health & Booking Assistant. The assistant is
available to anonymous visitors as a useful health-information and patient
acquisition feature. It is not initially offered as a configurable assistant
for other practices. Future authenticated and multi-practice variants require
separate decisions; do not build them prematurely.

## Intended experience

- Answer questions about Ballyclare services, fees, registration and booking
  using current, authoritative application data.
- Discuss symptoms conversationally, ask relevant clarifying questions,
  explain possible conditions with uncertainty, reference reviewed medical
  information, and recommend suitable next steps.
- Offer the existing guest booking flow where an ordinary consultation is
  appropriate. Do not imply a booking is confirmed without the existing
  authoritative payment and appointment services.
- Prioritise urgent or emergency care when warning signs arise; never use a
  sales prompt as a substitute for appropriate escalation.
- No anonymous access to patient records, clinical notes, private appointments
  or identity-linked information. Do not require registration to ask a public
  question. Minimise retention of potentially sensitive symptom descriptions.
- More advanced diagnostic functionality is a **future candidate**, not a
  launch commitment: define its intended medical purpose, undertake clinical
  validation and assess applicable medical-device, privacy and safety
  requirements before offering it to the public.

## Integration architecture

- Evaluate **RubyLLM** as the leading Ruby/Rails integration candidate, not
  an approved or installed dependency. Confirm current Rails compatibility,
  provider support, licensing, data processing terms and operational fit in a
  small proof of concept before selection.
- Put model calls behind application-owned `Ai::` services and explicit
  provider adapters. Controllers stay thin; domain services remain authoritative.
- Use reviewed knowledge-base content and attributable retrieval (Phase 8 then
  Phase 9) as grounding. Traditional search and non-AI fallback remain usable.
- Define explicit, least-privilege tools for practice information and booking
  discovery. Any consequential action requires Rails authorization, validation,
  domain-service enforcement and appropriate confirmation.
- Separate interactive latency-sensitive requests from background indexing,
  embeddings and analysis; use distinct queue capacity so AI cannot delay
  booking, payments, webhooks or refund recovery.
- Prefer efficient model routing, bounded context, selective safe caching and
  deterministic answers for straightforward FAQs. Measure per-feature requests,
  tokens, provider cost, latency, failures and quality. Set abuse protection,
  rate limits, budgets and alerts before anonymous launch.
- Establish versioned prompts, structured output validation, source tracking,
  evaluation fixtures and regression tests for red flags, uncertainty,
  hallucinations, prompt injection and cross-practice leakage.
- Before real health data or public symptom guidance: clinical governance,
  clinician-reviewed escalation criteria, privacy/data-protection impact
  assessment, provider retention and transfer review, jurisdiction-specific
  regulatory assessment, incident response and human oversight.

## Delivery gates

1. **Now / Phases 5–7:** keep reusable services, clear permission boundaries,
   and auditable domain operations; document AI-relevant decisions without
   installing model dependencies.
2. **Phase 8:** publish and review trusted medical content, including source
   provenance and a refresh policy.
3. **Phase 9:** deliver retrieval and the shared AI technical foundation,
   with benchmarked costs, latency, safety evaluations and provider fallback.
4. **Phase 10:** launch a limited public Ballyclare assistant only after
   clinical, privacy, regulatory, security and operational readiness review.
5. **Later:** assess authenticated patient and clinician experiences, deeper
   diagnostic support and reuse in other projects as separate milestones.

## Reuse across future projects

Preserve reusable patterns (provider abstraction, evaluations, cost metering,
background execution and safe tool interfaces) without coupling the current
healthcare assistant to a generic cross-industry product. Each future project
must define its own data permissions, intended purpose, risk controls and
release gates; sharing infrastructure does not imply sharing clinical data.

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

The recommended **next** sequence, following the October 2026 progress review,
is:

``` text
1. Verify Phase 4 gaps and finish the remaining Phase 5 portal acceptance work
        ↓
2. Staff-managed consultation fees by clinician type
        ↓
3. Secure patient registration and account linking
        ↓
4. Patient portal dashboard
        ↓
5. Patient self-booking with mandatory payment
        ↓
6. Patient appointment history / management
        ↓
7. Complete clinical encounter workflows
        ↓
8. Expanded services and fee catalogue
        ↓
9. Communications
        ↓
10. Medical Knowledge Base → Intelligent Retrieval and AI foundation → Ballyclare public AI Health & Booking Assistant
        ↓
11. Reporting / expanded administration
```

Security, privacy, payment resilience, accessibility, auditability, backup and
restore verification, and jurisdiction-specific compliance remain **continuous
requirements throughout**, not work deferred to the end.

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

The staff-booking and public guest-booking vertical slices are in place.
The authenticated patient portal remains a distinct Phase 5 workstream.
The next work should proceed in deliberately small, reviewed branches.

1. **Consultation fee configuration:** authorised staff edit per-practice
   doctor/nurse prices, initially £65/£40 at Ballyclare Medical. Establish a
   reusable pricing service and financial snapshot rules before changing
   booking forms or payment initiation.
2. **Patient registration:** map sign-up, practice selection, profile creation,
   email verification and secure links to pre-existing patient records. Review
   Devise configuration and prevent access to clinical records before verified
   linking.
3. **Portal foundation:** introduce patient-specific routes, layout,
   authentication/authorisation and a dashboard showing only that patient's
   appointments and balances.
4. **Patient-paid booking:** reuse shared availability, locking, pricing and
   domain rules. Acquire a hold, require payment and complete the appointment
   only on verified success, accounting for asynchronous and ambiguous provider
   outcomes.
5. **Patient management:** extend to history, receipts, later payments and
   permitted cancellations/rescheduling, with audit and clear refund policies.

For each step, include domain/service tests, request tests, appropriate system
tests, practice isolation, useful failures and responsive accessible UI.
For now, production deployments are for verified demonstration workflows;
**do not use real clinical/patient data** until security, privacy, compliance,
backups, restore processes and production operational controls are assessed.

------------------------------------------------------------------------

## Future Platform Reuse and Industry Adaptation

**Status: Long-term architectural consideration — not part of the current delivery scope**

Ballyclare Medical remains a healthcare-focused application. A future
beauty, wellness or other appointment-based business could reuse parts of
its scheduling, availability, booking, pricing, payments and notification
infrastructure, but changing `StaffMember::STAFF_TYPES` alone would not
make the application suitable for another industry.

Medical assumptions currently also appear in staff permissions, clinician
filters, consultation-fee validation and resolution, patient terminology,
encounters, clinical notes and other workflows. Those assumptions should
not be removed merely to make the current application appear generic.

### Preferred approach

- **Initially favour dedicated industry applications with reusable
  components and patterns** over one configurable multi-industry product.
- Keep the medical application's patient, clinical, privacy and
  authorisation boundaries explicit. Generic booking functionality must
  not accidentally grant access to healthcare information.
- As shared services evolve, avoid unnecessary healthcare-specific
  assumptions in availability, locking, booking, financial records,
  payment processing and provider adapters.
- Separate **staff profession or job title** from **access permissions**:
  being a doctor, nurse, beautician or nail specialist does not itself
  determine administrative authority.
- Separate **bookable services** from **staff types**. A salon may price
  manicures, facials and other treatments by service and duration rather
  than by the profession of the person delivering them. A future service
  catalogue may also be useful within healthcare.
- Preserve practice/organisation boundaries, historical charge snapshots,
  server-side pricing, auditability and concurrency guarantees in any
  extracted reusable functionality.

### Revisit later

After the patient portal and core medical workflows are established,
evaluate whether a separate industry-specific application should reuse
selected components, or whether genuine demand justifies a configurable
multi-industry platform. Any such decision needs an explicit review of
data models, terminology, service catalogues, roles and permissions,
industry-specific records, compliance, migration strategy and ongoing
maintenance cost.

**No immediate refactor or change to the current doctor/nurse consultation
fee policy is proposed.**

------------------------------------------------------------------------

# Decision Log (selected)

| Date | Decision | Rationale | Revisit when |
| --- | --- | --- | --- |
| 2026-10-27 | Public Ballyclare-only AI Health & Booking Assistant first | Patient discovery and useful symptom guidance, with existing guest booking as a conversion path | Authenticated or other-practice demand is validated |
| 2026-10-27 | Defer AI implementation; prepare service boundaries now | Avoid premature infrastructure while protecting later integration | Phase 9 planning or earlier AI dependency |
| 2026-10-27 | Evaluate RubyLLM, do not commit to a provider yet | Preserve portability, test real latency, cost and privacy | AI foundation proof of concept |
| 2026-10-27 | Keep Phase 5 authenticated portal distinct from public guest booking | Different identity, authorization and account-linking requirements | Phase 5 completion review |

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

15. **Consultation fees are configured per practice and clinician type.**
    Ballyclare Medical begins at £65 doctor / £40 nurse; staff can edit these
    settings. No initial per-clinician overrides. Historical charges keep
    their originally agreed values.

16. **Self-booking requires verified payment before appointment creation.**
    Staff-assisted booking may instead leave a balance due.

17. **Existing patient records are never linked to new logins by demographic
    matching alone.** Identity proof and authorisation precede access.

18. **Medical information follows the architecture:**

    ``` text
    Medical Knowledge Base → Intelligent Search/Retrieval → AI Assistant
    ```

19. **Ballyclare Medical remains healthcare-focused for now.**
    Reuse generic booking, availability, pricing and payment components
    where practical, but prefer dedicated industry applications before
    attempting a configurable multi-industry platform. Keep professions,
    permissions and bookable services distinct; revisit this only after
    the patient portal and core medical workflows mature.

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

**Last reviewed:** 27 October 2026. **Maintained in:** `docs/roadmap.md` on `main`.

This document should evolve with the product. Phase status is a delivery
assessment, not a substitute for checking current routes, code, tests and
production readiness. Record completed work separately from proposed work;
when uncertain, mark verification pending rather than assuming completion.

For substantial decisions, capture the date, decision, rationale, affected
phases, alternatives and conditions for revisiting it. Preserve history in Git
and link implementation details to issues/PRs. Review the roadmap at each
phase boundary and after major architectural or regulatory changes.

When a significant feature is merged:

1.  update its phase/status here;
2.  record important architectural decisions;
3.  move newly discovered work into the appropriate future phase;
4.  avoid turning the roadmap into a detailed issue tracker.

GitHub issues/PRs should contain implementation-level work.

This roadmap should remain the higher-level reference for **what we are
building, in what order, and why**.
